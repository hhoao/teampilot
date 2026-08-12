@Tags(['integration'])
@Timeout(Duration(minutes: 4))
library;

/// 真实 opencode CLI × 真实聊天界面 history 加载路径。
///
/// 启动真实 `opencode run` 流式回答(OPENCODE_DB 指向会话隔离目录,与
/// 聊天会话启动一致),期间像 AiHistorySeatCubit 的 live refresh 一样轮询
/// `AiHistoryLoader.load()`(真实 SessionHistoryContextBuilder → 真实
/// AiHistoryLocator → 真实 opencodeLiveCacheToken)。回答的问题:
/// 真实 CLI 在聊天界面跑的时候,history 加载到底走全量还是增量。
///
/// 行为(实现于 OpencodeHistoryIncrementalRefresher):
///  - 首次 load = 全量 locate + parse(之后 seed 指纹对齐);
///  - 流式期间 = DB 行级增量:只重读指纹变化的行,原地合并进 state 列表
///    (locate 不再被调用);
///  - 增量 tick 返回**新** List 实例(seat 的 identical 判定才感知变化);
///  - 空闲 = token 命中,零查询。
///
/// 判别信号:
///  - locate 次数:首次 load 后保持 1(不再全量 locate);
///  - 每个 poll 的消息 id 唯一(会话翻转/重复解析会混入同内容不同 id
///    的子会话消息 → 重复气泡);
///  - bundle hints:首次全量 locate 的 bundle 无 `incremental` 键。
///
/// 运行(需要本机安装 opencode 且已配置模型 provider):
///   flutter test test/integration/opencode_history_live_full_vs_incremental_integration_test.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import 'support/integration_prerequisites.dart';
import '../support/post_frame_test_harness.dart';

void main() {
  group('chat live refresh against the real opencode CLI', () {
    setUp(setUpTestAppStorage);
    tearDown(tearDownTestAppStorage);

    test('streaming writes → full reloads; idle → cache hit', () async {
      final opencode = IntegrationPrerequisites.requireOpencodePath();
      if (opencode == null) return;

      final base = Directory.systemTemp.createTempSync('opencode_live_hist_');
      final fs = LocalFilesystem();
      final layout = RuntimeLayout(teampilotRoot: base.path, fs: fs);
      final toolRoot = layout.sessionRuntimeToolDir(
        'ws-1',
        'sess-ui',
        'opencode',
      );
      Directory(toolRoot).createSync(recursive: true);
      final dbPath = p.join(toolRoot, 'opencode.db');
      final workDir = Directory(p.join(base.path, 'work'))..createSync();

      var started = false;
      var exited = false;
      final stdoutBuf = StringBuffer();
      final stderrBuf = StringBuffer();
      late Process process;
      addTearDown(() async {
        if (started && !exited) {
          process.kill(ProcessSignal.sigkill);
        }
        if (base.existsSync()) {
          base.deleteSync(recursive: true);
        }
      });

      process = await Process.start(
        opencode,
        [
          'run',
          'Write a short story about a cat named Mochi, about five sentences '
              'long. Reply with the story only.',
        ],
        workingDirectory: workDir.path,
        environment: {
          ...Platform.environment,
          'OPENCODE_DB': dbPath,
        },
      );
      started = true;
      unawaited(process.exitCode.then((_) => exited = true));
      process.stdout.transform(utf8.decoder).listen(stdoutBuf.write);
      process.stderr.transform(utf8.decoder).listen(stderrBuf.write);
      // `run` 模式不需要 stdin;不关闭会让部分版本阻塞在 stdin 读取。
      await process.stdin.close();

      final locator = _RecordingLocator();
      final loader = AiHistoryLoader(
        contextBuilder: const SessionHistoryContextBuilder(),
        resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
          target: RuntimeTarget.local(),
          filesystem: fs,
          home: base.path,
          cwd: base.path,
          appDataRoot: base.path,
          paths: AppPaths(base.path),
        ),
        registry: CliToolRegistry.builtIn(),
        locator: locator,
        // null → 真实 opencodeLiveCacheToken
        resolveCacheToken: null,
      );
      final session = AppSession(
        sessionId: 'sess-ui',
        workspaceId: 'ws-1',
        folders: const [WorkspaceFolder(path: '/work/project')],
        cli: CliTool.opencode,
        createdAt: 1,
        updatedAt: 1,
      );
      final ctx = WorkspaceLaunchContext(
        session: session,
        workspace: Workspace(
          workspaceId: session.workspaceId,
          folders: session.folders,
          createdAt: 1,
        ),
      );

      // 聊天界面 live refresh 循环:进程存活期间每 250ms 一次 load。
      final polls = <_Poll>[];
      final deadline = DateTime.now().add(const Duration(seconds: 120));
      while (!exited && DateTime.now().isBefore(deadline)) {
        final result = await loader.load(
          session: session,
          memberId: '',
          launchContext: ctx,
        );
        polls.add(
          _Poll(
            locateCalls: locator.calls,
            bundle: locator.lastBundle,
            messages: result.messages,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (!exited) {
        process.kill(ProcessSignal.sigkill);
      }

      // 进程退出后 settle(WAL checkpoint),再做最终 load + 空闲 load。
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final settled = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      final idle = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );

      expect(
        polls.where((poll) => poll.locateCalls > 0),
        isNotEmpty,
        reason: '首次 load 必须全量 locate。stdout:\n$stdoutBuf\n'
            'stderr:\n$stderrBuf',
      );

      // 1) 首次 locate 产出的 bundle 是全量 SQLite 定位(无 incremental 键),
      //    且整个流式期间 locate 只发生一次(之后全是行级增量)。
      final locatedPolls = polls
          .where((poll) => poll.locateCalls > 0 && poll.bundle != null)
          .toList();
      expect(
        locatedPolls,
        isNotEmpty,
        reason: '首次 load 应产生全量 bundle',
      );
      for (final poll in locatedPolls) {
        final hints = poll.bundle!.hints;
        expect(
          hints['source'],
          'sqlite',
          reason: '真实 CLI 的 transcript 在 opencode.db',
        );
        expect(
          hints['incremental'],
          isNull,
          reason: '首次 load 走全量 locate(增量从第二次 load 开始)',
        );
      }
      final firstBundlePoll = polls.indexWhere((poll) => poll.bundle != null);
      expect(
        firstBundlePoll,
        greaterThanOrEqualTo(0),
        reason: '必须出现首个全量 bundle',
      );
      expect(
        polls.last.locateCalls,
        polls[firstBundlePoll].locateCalls,
        reason: '首次全量 locate 之后,流式期间不再全量 locate'
            '(数据变动 = 行级增量)',
      );

      // 2) 首次全量之后:每个 poll 的消息列表不得出现重复消息 id /
      //    重复 user 文本——增量路径被 seat 的 identical 判定吞掉会缺消息,
      //    会话翻转(子会话变成最新)会混入同内容不同 id 的子会话消息,
      //    页面出现重复气泡。
      for (var i = firstBundlePoll + 1; i < polls.length; i++) {
        final ids = [for (final m in polls[i].messages) m.id];
        expect(
          ids.toSet().length,
          ids.length,
          reason: 'poll #$i 出现重复消息 id(重复气泡/会话翻转混入)',
        );
        final userTexts = [
          for (final m in polls[i].messages)
            if (m.role == AiRole.user)
              for (final p in m.parts)
                if (p is AiTextPart) p.text,
        ];
        expect(
          userTexts.toSet().length,
          userTexts.length,
          reason: 'poll #$i 出现重复 user 文本(子会话混入 seat 列表)',
        );
      }

      // 3) 真实回答最终可见。
      final assistantText = _assistantText(settled.messages);
      expect(
        assistantText.trim(),
        isNotEmpty,
        reason: '最终 load 必须包含真实 assistant 回答。stdout:\n$stdoutBuf',
      );

      // 4) 空闲后再 load → 零 locate,同一实例。
      final settledLocateCalls = locator.calls;
      expect(
        identical(idle.messages, settled.messages),
        isTrue,
        reason: '空闲 reload 必须复用同一 List 实例(缓存命中)',
      );
      expect(
        locator.calls,
        settledLocateCalls,
        reason: '空闲 reload 连 locate 都不进',
      );
    });

    test('child session flipping newest must not mix into the seat transcript',
        () async {
      final opencode = IntegrationPrerequisites.requireOpencodePath();
      if (opencode == null) return;

      final base = Directory.systemTemp.createTempSync('opencode_live_flip_');
      final fs = LocalFilesystem();
      final layout = RuntimeLayout(teampilotRoot: base.path, fs: fs);
      final toolRoot = layout.sessionRuntimeToolDir(
        'ws-1',
        'sess-ui',
        'opencode',
      );
      Directory(toolRoot).createSync(recursive: true);
      final dbPath = p.join(toolRoot, 'opencode.db');
      final workDir = Directory(p.join(base.path, 'work'))..createSync();

      var started = false;
      var exited = false;
      final stdoutBuf = StringBuffer();
      late Process process;
      addTearDown(() async {
        if (started && !exited) {
          process.kill(ProcessSignal.sigkill);
        }
        if (base.existsSync()) {
          base.deleteSync(recursive: true);
        }
      });

      process = await Process.start(
        opencode,
        [
          'run',
          'Write a short story about a cat named Mochi, about five sentences '
              'long. Reply with the story only.',
        ],
        workingDirectory: workDir.path,
        environment: {
          ...Platform.environment,
          'OPENCODE_DB': dbPath,
        },
      );
      started = true;
      unawaited(process.exitCode.then((_) => exited = true));
      process.stdout.transform(utf8.decoder).listen(stdoutBuf.write);
      await process.stdin.close();

      final locator = _RecordingLocator();
      final loader = AiHistoryLoader(
        contextBuilder: const SessionHistoryContextBuilder(),
        resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
          target: RuntimeTarget.local(),
          filesystem: fs,
          home: base.path,
          cwd: base.path,
          appDataRoot: base.path,
          paths: AppPaths(base.path),
        ),
        registry: CliToolRegistry.builtIn(),
        locator: locator,
        // null → 真实 opencodeLiveCacheToken;session 无 nativeSessionIds
        // → _resolveSessionId 走"最新会话"回退,复现无绑定场景。
        resolveCacheToken: null,
      );
      final session = AppSession(
        sessionId: 'sess-ui',
        workspaceId: 'ws-1',
        folders: const [WorkspaceFolder(path: '/work/project')],
        cli: CliTool.opencode,
        createdAt: 1,
        updatedAt: 1,
      );
      final ctx = WorkspaceLaunchContext(
        session: session,
        workspace: Workspace(
          workspaceId: session.workspaceId,
          folders: session.folders,
          createdAt: 1,
        ),
      );

      // 轮询到首次真实 locate 成功(bundle 非空 = schema 已建、seed 完成)
      // 再注入子会话。
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      var firstLocate = 0;
      while (DateTime.now().isBefore(deadline)) {
        await loader.load(
          session: session,
          memberId: '',
          launchContext: ctx,
        );
        firstLocate = locator.calls;
        if (locator.lastBundle != null && !exited) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      expect(firstLocate, greaterThan(0), reason: '必须完成首次全量 locate');
      expect(locator.lastBundle, isNotNull, reason: '首次 locate 必须成功');

      // 注入 task 子会话:time_updated 最新 → 旧实现会把"最新会话"解析成
      // 子会话,增量指纹/重读全落在子会话上 → 回退全量 + 子会话内容混入。
      final marker = 'CHILD-MARKER-${DateTime.now().microsecondsSinceEpoch}';
      final child = sqlite3.open(dbPath);
      try {
        final seatRows = child.select(
          'SELECT id, time_updated FROM session ORDER BY time_updated DESC '
          'LIMIT 1',
        );
        final seatUpdated = seatRows.isEmpty
            ? 0
            : (seatRows.first['time_updated'] as int?) ?? 0;
        final newest = seatUpdated + 100000;
        // 真实 schema 的 NOT NULL 列需全部提供(project_id/slug/...)。
        child.execute(
          'INSERT INTO session (id, project_id, slug, directory, title, '
          'version, cost, tokens_input, tokens_output, tokens_reasoning, '
          'tokens_cache_read, tokens_cache_write, time_created, time_updated) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            'ses_child',
            'global',
            'child-test',
            '/tmp/child',
            'child-test',
            '1.18.4',
            0,
            0,
            0,
            0,
            0,
            0,
            newest,
            newest,
          ],
        );
        child.execute(
          'INSERT INTO message (id, session_id, data, time_created, '
          'time_updated) VALUES (?, ?, ?, ?, ?)',
          [
            'msg_child_1',
            'ses_child',
            jsonEncode({
              'role': 'user',
              'time': {'created': newest + 1},
            }),
            newest + 1,
            newest + 1,
          ],
        );
        child.execute(
          'INSERT INTO part (id, session_id, message_id, data, time_created, '
          'time_updated) VALUES (?, ?, ?, ?, ?, ?)',
          [
            'part_child_1',
            'ses_child',
            'msg_child_1',
            jsonEncode({'type': 'text', 'text': marker}),
            newest + 1,
            newest + 1,
          ],
        );
      } finally {
        child.dispose();
      }

      // 子会话活跃期间继续轮询到 CLI 退出。
      final polls = <_Poll>[];
      final pollDeadline = DateTime.now().add(const Duration(seconds: 90));
      while (!exited && DateTime.now().isBefore(pollDeadline)) {
        final result = await loader.load(
          session: session,
          memberId: '',
          launchContext: ctx,
        );
        polls.add(
          _Poll(
            locateCalls: locator.calls,
            bundle: locator.lastBundle,
            messages: result.messages,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (!exited) {
        process.kill(ProcessSignal.sigkill);
      }
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final settled = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      polls.add(
        _Poll(
          locateCalls: locator.calls,
          bundle: locator.lastBundle,
          messages: settled.messages,
        ),
      );

      expect(
        polls.map((poll) => poll.locateCalls).toSet().length,
        1,
        reason: '子会话变成最新会话不得触发全量回退(旧实现每轮重复解析)。'
            'locate 次数: ${polls.map((p) => p.locateCalls).toSet()}',
      );
      for (var i = 0; i < polls.length; i++) {
        final texts = [
          for (final m in polls[i].messages)
            for (final p in m.parts)
              if (p is AiTextPart) p.text,
        ];
        expect(
          texts.any((t) => t.contains(marker)),
          isFalse,
          reason: 'poll #$i 混入了子会话消息(同内容不同 id → 重复气泡)',
        );
        final ids = [for (final m in polls[i].messages) m.id];
        expect(
          ids.toSet().length,
          ids.length,
          reason: 'poll #$i 出现重复消息 id',
        );
      }
      expect(
        _assistantText(settled.messages).trim(),
        isNotEmpty,
        reason: 'seat 会话的回答必须完整可见。stdout:\n$stdoutBuf',
      );
    });
  });
}

String _assistantText(List<AiMessage> messages) {
  return [
    for (final m in messages)
      for (final part in m.parts)
        if (part is AiTextPart && m.role == AiRole.assistant) part.text,
  ].join('\n');
}

class _Poll {
  const _Poll({
    required this.locateCalls,
    required this.bundle,
    required this.messages,
  });

  final int locateCalls;
  final AiTranscriptBundle? bundle;
  final List<AiMessage> messages;
}

class _RecordingLocator extends AiHistoryLocator {
  _RecordingLocator() : super();

  int calls = 0;
  AiTranscriptBundle? lastBundle;

  @override
  Future<AiTranscriptBundle?> locate({
    required SessionHistoryContext ctx,
    required CliTool cli,
  }) async {
    calls++;
    final bundle = await super.locate(ctx: ctx, cli: cli);
    lastBundle = bundle;
    return bundle;
  }
}
