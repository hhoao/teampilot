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
///  - 流式期间 = DB 行级增量:只重读指纹变化的行,**原地**合并进同一
///    List 实例(locate 不再被调用,消息列表实例跨 refresh 不变);
///  - 空闲 = token 命中,零查询。
///
/// 判别信号:
///  - locate 次数:首次 load 后保持 1(不再全量 locate);
///  - `identical(messages)`:增量原地合并,跨 refresh 复用同一 List 实例;
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

      // 2) 首次全量之后:列表实例在流式期间保持恒同(增量原地合并 /
      //    缓存命中都复用同一 List 实例;全量路径每次都是新实例)。
      for (var i = firstBundlePoll + 1; i < polls.length; i++) {
        expect(
          identical(polls[i].messages, polls[i - 1].messages),
          isTrue,
          reason: '首次全量之后不得再产生新 List 实例(no full re-parse)',
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
