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
import 'package:teampilot/services/cli/opencode/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/opencode/capabilities/sqlite_worker_pool.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_load_result.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../../../support/post_frame_test_harness.dart';

/// 聊天界面 live refresh 的端到端模拟:真实 opencode.db(SQLite+WAL,
/// 写连接保持打开) + 真实 context builder → locator → loader(真实
/// `opencodeLiveCacheToken`),与 AiHistorySeatCubit 每轮 refresh 调用
/// `loader.load()` 的路径完全一致。回答:"聊天界面跑的时候到底走全量
/// 还是增量"。
///
/// 行为:
///  - 首次 load = page-first 最近窗,不 locate;page 已覆盖全部消息时直接
///    complete 并复用解码结果,不再二次 locate(9aa9a172e 免二次解码);
///    后台 full index 才 seed [OpencodeHistoryIncrementalRefresher];
///  - store 变动且增量已对齐 = DB 行级增量:只重读指纹变化的行,原地
///    合并,不再全量 locate / 全量 parse;
///  - 子 agent 附件按需 `loadSubagentAttachmentForSeat`,首屏不 eager
///    inflate;
///  - 删除/压缩/schema 不兼容 = 回退全量。
///
/// 判别信号:
///  - locate 调用次数:page-first 为 0,增量后保持 0;只有回退全量才 >0;
///  - `identical(messages)`:增量原地合并,跨 refresh 复用未变化实例。
void main() {
  late Directory base;
  late LocalFilesystem fs;
  late RuntimeLayout layout;
  late String toolRoot;
  late String dbPath;
  late Database writer;

  setUp(() {
    setUpTestAppStorage();
    base = Directory.systemTemp.createTempSync('opencode_full_vs_incr_');
    fs = LocalFilesystem();
    layout = RuntimeLayout(teampilotRoot: base.path, fs: fs);
    toolRoot = layout.sessionRuntimeToolDir('ws-1', 'sess-ui', 'opencode');
    Directory(toolRoot).createSync(recursive: true);
    dbPath = p.join(toolRoot, 'opencode.db');
  });

  tearDown(() async {
    try {
      writer.close();
    } on Object {
      // already closed
    }
    await OpencodeSqliteWorkerPool.instance.disposeAllAndWait();
    if (base.existsSync()) {
      base.deleteSync(recursive: true);
    }
    tearDownTestAppStorage();
    clearOpencodeParentMemo();
  });

  AppSession opencodeSession() => AppSession(
    sessionId: 'sess-ui',
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/work/project')],
    cli: CliTool.opencode,
    createdAt: 1,
    updatedAt: 1,
    nativeSessionIds: const {'opencode': 'ses_1'},
  );

  WorkspaceLaunchContext launchContextFor(AppSession session) =>
      WorkspaceLaunchContext(
        session: session,
        workspace: Workspace(
          workspaceId: session.workspaceId,
          folders: session.folders,
          createdAt: 1,
        ),
      );

  RuntimeContext fixedRoots() => RuntimeContext(
    target: RuntimeTarget.local(),
    filesystem: fs,
    home: base.path,
    cwd: base.path,
    appDataRoot: base.path,
    paths: AppPaths(base.path),
  );

  /// 现代 schema:part 表带 `time_updated`(opencode 2025+ v1 存储)。
  /// 写连接保持打开并启用 WAL,模拟运行中的 CLI。
  void openModernDb() {
    writer = sqlite3.open(dbPath);
    writer.execute('PRAGMA journal_mode=WAL;');
    writer.execute('''
    CREATE TABLE session (
      id TEXT PRIMARY KEY,
      parent_id TEXT,
      time_created INTEGER NOT NULL,
      time_updated INTEGER NOT NULL
    )''');
    writer.execute('''
    CREATE TABLE message (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      data TEXT NOT NULL,
      time_created INTEGER NOT NULL,
      time_updated INTEGER NOT NULL
    )''');
    writer.execute('''
    CREATE TABLE part (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      message_id INTEGER NOT NULL,
      data TEXT NOT NULL,
      time_created INTEGER NOT NULL,
      time_updated INTEGER NOT NULL
    )''');
    writer.execute(
      'INSERT INTO session (id, time_created, time_updated) VALUES (?, ?, ?)',
      ['ses_1', 1000, 1000],
    );
  }

  /// 旧 schema:part 表没有 `time_updated`(本仓库测试 fixture
  /// opencode_ai_transcript_test 建模的版本)。
  void openLegacyDb() {
    writer = sqlite3.open(dbPath);
    writer.execute('PRAGMA journal_mode=WAL;');
    writer.execute('''
    CREATE TABLE session (
      id TEXT PRIMARY KEY,
      time_updated INTEGER NOT NULL
    )''');
    writer.execute('''
    CREATE TABLE message (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      data TEXT NOT NULL,
      time_created INTEGER NOT NULL
    )''');
    writer.execute('''
    CREATE TABLE part (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      message_id INTEGER NOT NULL,
      data TEXT NOT NULL,
      time_created INTEGER NOT NULL
    )''');
    writer.execute(
      'INSERT INTO session (id, time_updated) VALUES (?, ?)',
      ['ses_1', 1000],
    );
  }

  void insertMessage({
    required int id,
    required String role,
    required int created,
    bool withTimeUpdated = true,
  }) {
    final data = jsonEncode({
      'role': role,
      'time': {'created': created},
    });
    if (withTimeUpdated) {
      writer.execute(
        'INSERT INTO message (id, session_id, data, time_created, time_updated) '
        'VALUES (?, ?, ?, ?, ?)',
        [id, 'ses_1', data, created, created],
      );
    } else {
      writer.execute(
        'INSERT INTO message (id, session_id, data, time_created) '
        'VALUES (?, ?, ?, ?)',
        [id, 'ses_1', data, created],
      );
    }
  }

  void insertPart({
    required int id,
    required int messageId,
    required String text,
    required int created,
    bool withTimeUpdated = true,
    bool withSessionId = true,
  }) {
    final data = jsonEncode({'type': 'text', 'text': text});
    if (withTimeUpdated) {
      writer.execute(
        'INSERT INTO part (id, session_id, message_id, data, time_created, '
        'time_updated) VALUES (?, ?, ?, ?, ?, ?)',
        [id, 'ses_1', messageId, data, created, created],
      );
    } else if (withSessionId) {
      writer.execute(
        'INSERT INTO part (id, session_id, message_id, data, time_created) '
        'VALUES (?, ?, ?, ?, ?)',
        [id, 'ses_1', messageId, data, created],
      );
    } else {
      writer.execute(
        'INSERT INTO part (id, message_id, data, time_created) '
        'VALUES (?, ?, ?, ?)',
        [id, messageId, data, created],
      );
    }
  }

  /// 种子:1 条 user 消息 + 1 条 assistant 消息。
  void seedConversation({bool legacy = false}) {
    insertMessage(id: 1, role: 'user', created: 1000, withTimeUpdated: !legacy);
    insertPart(
      id: 1,
      messageId: 1,
      text: 'hi',
      created: 1000,
      withTimeUpdated: !legacy,
      withSessionId: !legacy,
    );
    insertMessage(
      id: 2,
      role: 'assistant',
      created: 2000,
      withTimeUpdated: !legacy,
    );
    insertPart(
      id: 2,
      messageId: 2,
      text: 'hello',
      created: 2000,
      withTimeUpdated: !legacy,
      withSessionId: !legacy,
    );
  }

  /// 已完成 task 调用:父消息 + tool part(输出携带 `<task id="ses_…">`) +
  /// 子会话(session/message/part 行)。
  void insertTaskCallAndChild({
    required int messageId,
    required int created,
    required String toolCallId,
    required String childSessionId,
    required String output,
  }) {
    writer.execute(
      'INSERT INTO message (id, session_id, data, time_created, time_updated) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        messageId,
        'ses_1',
        jsonEncode({'role': 'assistant', 'time': {'created': created}}),
        created,
        created,
      ],
    );
    writer.execute(
      'INSERT INTO part (id, session_id, message_id, data, time_created, '
      'time_updated) VALUES (?, ?, ?, ?, ?, ?)',
      [
        messageId * 1000,
        'ses_1',
        messageId,
        jsonEncode({
          'type': 'tool',
          'tool': 'task',
          'callID': toolCallId,
          'state': {
            'status': 'completed',
            'input': {'prompt': 'x'},
            'output': output,
          },
        }),
        created,
        created,
      ],
    );
    writer.execute(
      'INSERT INTO session (id, parent_id, time_created, time_updated) '
      'VALUES (?, ?, ?, ?)',
      [childSessionId, 'ses_1', created + 1, created + 1],
    );
    writer.execute(
      'INSERT INTO message (id, session_id, data, time_created, time_updated) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        messageId * 100,
        childSessionId,
        jsonEncode({'role': 'user', 'time': {'created': created + 2}}),
        created + 2,
        created + 2,
      ],
    );
    writer.execute(
      'INSERT INTO part (id, session_id, message_id, data, time_created, '
      'time_updated) VALUES (?, ?, ?, ?, ?, ?)',
      [
        messageId * 1000 + 1,
        childSessionId,
        messageId * 100,
        jsonEncode({'type': 'text', 'text': 'child output $messageId'}),
        created + 2,
        created + 2,
      ],
    );
  }

  /// 运行中的 task 调用:父 part status=running、output 为空;子会话已存在。
  void insertRunningTaskCall({
    required int messageId,
    required int created,
    required String toolCallId,
    required String childSessionId,
  }) {
    writer.execute(
      'INSERT INTO message (id, session_id, data, time_created, time_updated) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        messageId,
        'ses_1',
        jsonEncode({'role': 'assistant', 'time': {'created': created}}),
        created,
        created,
      ],
    );
    writer.execute(
      'INSERT INTO part (id, session_id, message_id, data, time_created, '
      'time_updated) VALUES (?, ?, ?, ?, ?, ?)',
      [
        messageId * 1000,
        'ses_1',
        messageId,
        jsonEncode({
          'type': 'tool',
          'tool': 'task',
          'callID': toolCallId,
          'state': {'status': 'running', 'input': {'prompt': 'x'}},
        }),
        created,
        created,
      ],
    );
    writer.execute(
      'INSERT INTO session (id, parent_id, time_created, time_updated) '
      'VALUES (?, ?, ?, ?)',
      [childSessionId, 'ses_1', created + 1, created + 1],
    );
    writer.execute(
      'INSERT INTO message (id, session_id, data, time_created, time_updated) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        messageId * 100,
        childSessionId,
        jsonEncode({'role': 'user', 'time': {'created': created + 2}}),
        created + 2,
        created + 2,
      ],
    );
    writer.execute(
      'INSERT INTO part (id, session_id, message_id, data, time_created, '
      'time_updated) VALUES (?, ?, ?, ?, ?, ?)',
      [
        messageId * 1000 + 1,
        childSessionId,
        messageId * 100,
        jsonEncode({'type': 'text', 'text': 'child running $messageId'}),
        created + 2,
        created + 2,
      ],
    );
  }

  /// 包裹真实 locator 的计数器:记录 locate 次数、最后一次 ctx 与每个
  /// bundle(用于 hint 断言与 seat 级 memo 的 identical 检查)。
  late _RecordingLocator locator;

  AiHistoryLoader buildLoader() {
    locator = _RecordingLocator();
    return AiHistoryLoader(
      contextBuilder: const SessionHistoryContextBuilder(),
      resolveWorkContext: (_, {String? memberId}) async => fixedRoots(),
      registry: CliToolRegistry.builtIn(),
      locator: locator,
      // null → 真实能力 token(opencodeLiveCacheToken)
      resolveCacheToken: null,
    );
  }

  Future<AiHistoryLoadResult> warmFullIndex(
    AiHistoryLoader loader,
    AppSession session,
  ) async {
    final full = await loader.fullIndex(
      sessionId: session.sessionId,
      memberId: '',
    );
    expect(full, isNotNull, reason: 'page-first 必须调度后台 full index');
    return full!;
  }

  Future<AiSubagentAttachment?> loadAttachment({
    required AiHistoryLoader loader,
    required AppSession session,
    required WorkspaceLaunchContext ctx,
    required String toolCallId,
    required List<AiMessage> messages,
  }) {
    return loader.loadSubagentAttachmentForSeat(
      session: session,
      memberId: '',
      launchContext: ctx,
      toolCallId: toolCallId,
      messages: messages,
    );
  }

  group('chat live refresh (modern schema, part.time_updated exists)', () {
    test('idle seat: token gate + seat memo skip locate/parse entirely', () async {
      openModernDb();
      seedConversation();
      final loader = buildLoader();
      final session = opencodeSession();
      final ctx = launchContextFor(session);

      final first = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(first.messages, hasLength(2));
      expect(locator.calls, 0, reason: '首屏 page-first,不 locate');
      expect(
        first.isComplete,
        isTrue,
        reason: '首页已覆盖全部消息 → 直接 complete(免二次解码)',
      );

      final full = await warmFullIndex(loader, session);
      expect(
        locator.calls,
        0,
        reason: 'page 已覆盖全文 → full index 复用 page 结果,不再二次 locate',
      );
      expect(
        identical(full.messages, first.messages),
        isTrue,
        reason: 'double-decode 规避:full index 复用 page-first 的解码实例',
      );

      // 聊天界面空闲轮询:store 级 token 未变 → 缓存命中,零 locate。
      final second = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(locator.calls, 0, reason: '未变化时连 locate 都不进');
      expect(
        identical(second.messages, full.messages),
        isTrue,
        reason: '缓存命中必须复用同一 List 实例',
      );

      // seat 级 _parentBundles memo:直接 locate 两次,指纹未变 → 同一实例。
      final locateCtx = const SessionHistoryContextBuilder().build(
        fs: fs,
        layout: layout,
        appDataRoot: base.path,
        session: session,
        memberId: '',
        cli: CliTool.opencode,
      );
      final b1 = await locator.locate(
        ctx: locateCtx,
        cli: CliTool.opencode,
      );
      final b2 = await locator.locate(
        ctx: locateCtx,
        cli: CliTool.opencode,
      );
      expect(
        identical(b1, b2),
        isTrue,
        reason: 'seat 指纹未变时 parentBundles memo 直接命中,不重跑 SQL',
      );
    });

    test(
      'token change before full index re-reads the page without locating',
      () async {
        openModernDb();
        seedConversation();
        final loader = buildLoader();
        final session = opencodeSession();
        final ctx = launchContextFor(session);

        final first = await loader.load(
          session: session,
          memberId: '',
          launchContext: ctx,
        );
        expect(locator.calls, 0, reason: '首屏 page-first');
        expect(
          first.isComplete,
          isTrue,
          reason: '首页覆盖全部消息 → 直接 complete',
        );

        writer.execute(
          "UPDATE part SET data = ?, time_updated = 3000 WHERE id = 2",
          [jsonEncode({'type': 'text', 'text': 'hello chunk'})],
        );

        final second = await loader
            .load(
              session: session,
              memberId: '',
              launchContext: ctx,
            )
            .timeout(
              const Duration(seconds: 2),
              onTimeout: () => fail(
                'second load waited on full locate; empty incremental state '
                'must not skip readLatest',
              ),
            );

        expect(
          second.isComplete,
          isTrue,
          reason: '重读后的 page 仍覆盖全部消息 → complete',
        );
        expect(
          second.messages.any(
            (m) => m.parts.any(
              (p) => p is AiTextPart && p.text.contains('hello chunk'),
            ),
          ),
          isTrue,
        );
        expect(
          locator.calls,
          0,
          reason: 'live refresh 仍走 page-first,不 locate',
        );
      },
    );

    test('streaming append (new rows + in-place growth): incremental in-place merge',
        () async {
      openModernDb();
      seedConversation();
      final loader = buildLoader();
      final session = opencodeSession();
      final ctx = launchContextFor(session);

      final first = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(locator.calls, 0, reason: '首屏 page-first');
      final baseline = await warmFullIndex(loader, session);
      expect(locator.calls, 0, reason: 'full index 复用 page 结果,不 locate');

      // CLI 流式写入:新增 assistant 消息 + 原地增长已有 text part 行
      // (time_updated 前进,count 与行内容都变)。
      writer.execute(
        "UPDATE part SET data = ?, time_updated = 3000 WHERE id = 2",
        [jsonEncode({'type': 'text', 'text': 'hello chunk'})],
      );
      insertMessage(id: 3, role: 'assistant', created: 3000);
      insertPart(id: 3, messageId: 3, text: 'world', created: 3000);

      final second = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(locator.calls, 0, reason: 'store 动了 → 走 DB 行级增量,不 locate');
      expect(
        second.messages.any(
          (m) => m.parts.any(
            (p) => p is AiTextPart && p.text.contains('hello chunk'),
          ),
        ),
        isTrue,
      );
      expect(
        second.messages.any(
          (m) => m.parts.any(
            (p) => p is AiTextPart && p.text.contains('world'),
          ),
        ),
        isTrue,
      );
      expect(
        identical(second.messages, baseline.messages),
        isFalse,
        reason: '增量路径必须返回新 List 实例:state 列表被原地变异,若复用同一'
            '实例,seat 的 identical 判定("CLI 未变化")会把新内容当成没变而'
            '跳过,页面永远不出现增量消息',
      );
      expect(
        identical(second.messages[0], baseline.messages[0]),
        isTrue,
        reason: '未变化消息保持实例身份(附件/下游 identical 快速路径)',
      );
      expect(first.isComplete, isTrue);
    });

    test('task call appended after first load enters subagent attachments',
        () async {
      openModernDb();
      seedConversation();
      // 第一个已完成 task 调用 + 其子会话(结果字符串携带子会话 id)。
      insertTaskCallAndChild(
        messageId: 3,
        created: 3000,
        toolCallId: 'toolu_1',
        childSessionId: 'ses_2',
        output: '<task id="ses_2" state="completed">done 1</task>',
      );
      final loader = buildLoader();
      final session = opencodeSession();
      final ctx = launchContextFor(session);

      final first = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(first.subagentAttachments, isEmpty, reason: '首屏不 eager inflate');
      final full = await warmFullIndex(loader, session);
      final firstAttachment = await loadAttachment(
        loader: loader,
        session: session,
        ctx: ctx,
        toolCallId: 'toolu_1',
        messages: full.messages,
      );
      expect(firstAttachment, isNotNull);
      expect(firstAttachment!.toolCallId, 'toolu_1');

      // CLI 追加第二个 task 调用 + 第二个子会话:store 级增量只重读变化的
      // 行,不会重跑全量 parse——附件索引必须跟上新出现的调用。
      insertTaskCallAndChild(
        messageId: 4,
        created: 4000,
        toolCallId: 'toolu_2',
        childSessionId: 'ses_3',
        output: '<task id="ses_3" state="completed">done 2</task>',
      );
      final second = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );

      expect(
        second.subagentAttachments.keys,
        contains('toolu_1'),
        reason: '已按需加载的附件在签名未变时必须保留',
      );
      expect(
        second.subagentAttachments.keys,
        isNot(contains('toolu_2')),
        reason: '增量 tick 不得 eager inflate 尚未打开的子会话',
      );
      final secondAttachment = await loadAttachment(
        loader: loader,
        session: session,
        ctx: ctx,
        toolCallId: 'toolu_2',
        messages: second.messages,
      );
      expect(secondAttachment, isNotNull);
      expect(
        second.subagentAttachments.keys,
        containsAll(['toolu_1', 'toolu_2']),
        reason: 'DB 增量 tick 后新出现的 task 调用必须能按需 inflate——否则'
            '点击预览会提示"无法打开该子会话预览"(subagentPreviewUnavailable)',
      );
    });

    test('running child growth stays on the snapshot until the task completes',
        () async {
      openModernDb();
      seedConversation();
      // 运行中的 task:父 part 为 running 且 output 为空(adapter 契约:
      // running 状态不带 result);子会话 ses_2 有一条消息(等待 discovery)。
      insertRunningTaskCall(
        messageId: 3,
        created: 3000,
        toolCallId: 'toolu_1',
        childSessionId: 'ses_2',
      );
      final loader = buildLoader();
      final session = opencodeSession();
      final ctx = launchContextFor(session);

      final first = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(first.subagentAttachments, isEmpty);
      final full = await warmFullIndex(loader, session);
      final firstAttachment = await loadAttachment(
        loader: loader,
        session: session,
        ctx: ctx,
        toolCallId: 'toolu_1',
        messages: full.messages,
      );
      expect(
        firstAttachment,
        isNotNull,
        reason: '运行中的 task 必须通过 discovery 找到子会话',
      );
      expect(
        firstAttachment!.messages,
        hasLength(1),
        reason: '首次解析时子会话只有一条消息',
      );

      // 子 agent 继续输出(子会话追加消息),但父 part 冻结:签名不变 →
      // 附件索引必须复用,不空转重解析,预览停留在快照。
      writer.execute(
        'INSERT INTO message (id, session_id, data, time_created, '
        'time_updated) VALUES (?, ?, ?, ?, ?)',
        [
          301,
          'ses_2',
          jsonEncode({'role': 'assistant', 'time': {'created': 3500}}),
          3500,
          3500,
        ],
      );
      writer.execute(
        'INSERT INTO part (id, session_id, message_id, data, time_created, '
        'time_updated) VALUES (?, ?, ?, ?, ?, ?)',
        [
          3003,
          'ses_2',
          301,
          jsonEncode({'type': 'text', 'text': 'more progress'}),
          3500,
          3500,
        ],
      );
      final middle = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(
        identical(
          middle.subagentAttachments['toolu_1']!.messages,
          firstAttachment.messages,
        ),
        isTrue,
        reason: '父 part 冻结时子会话增长不可见(签名不变 → 复用快照),'
            '不产生无谓的重解析',
      );

      // 任务完成:父 part 更新为 completed + 输出携带子会话 id → 签名变化
      // → 重新 inflate,预览刷新到子会话的最新完整内容。
      writer.execute(
        'UPDATE part SET data = ?, time_updated = 3600 WHERE id = 3000',
        [
          jsonEncode({
            'type': 'tool',
            'tool': 'task',
            'callID': 'toolu_1',
            'state': {
              'status': 'completed',
              'input': {'prompt': 'x'},
              'output': '<task id="ses_2" state="completed">done</task>',
            },
          }),
        ],
      );
      final second = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );

      final secondAttachment = await loadAttachment(
        loader: loader,
        session: session,
        ctx: ctx,
        toolCallId: 'toolu_1',
        messages: second.messages,
      );
      expect(secondAttachment, isNotNull);
      expect(
        secondAttachment!.messages,
        hasLength(2),
        reason: '调用完成(part 状态/结果变化)后必须重新解析,预览跟随到'
            '子会话的最新完整内容',
      );
      expect(
        (secondAttachment.messages.last.parts.single as AiTextPart).text,
        'more progress',
      );
    });

    test('in-place growth only (count unchanged): incremental replace', () async {
      openModernDb();
      seedConversation();
      final loader = buildLoader();
      final session = opencodeSession();
      final ctx = launchContextFor(session);

      final first = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(locator.calls, 0, reason: '首屏 page-first');
      final baseline = await warmFullIndex(loader, session);
      expect(locator.calls, 0);

      // 只有一条流式 text 原地增长:行数不变,MAX(time_updated) 前进。
      writer.execute(
        "UPDATE part SET data = ?, time_updated = 4000 WHERE id = 2",
        [jsonEncode({'type': 'text', 'text': 'hello grow'})],
      );

      final second = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(locator.calls, 0, reason: '原地增长 → 行级增量,不 locate');
      expect(
        second.messages.any(
          (m) => m.parts.any(
            (p) => p is AiTextPart && p.text.contains('hello grow'),
          ),
        ),
        isTrue,
      );
      expect(
        identical(second.messages, baseline.messages),
        isFalse,
        reason: '原地增长也必须返回新 List 实例(同 seat identical 判定问题)',
      );
      expect(
        identical(second.messages[0], baseline.messages[0]),
        isTrue,
        reason: '未变化消息保持实例身份',
      );
      expect(first.isComplete, isTrue);
    });

    test('task child session becoming newest must not flip the seat transcript',
        () async {
      openModernDb();
      seedConversation();
      // 无 persisted native id → _resolveSessionId 走"最新会话"回退,
      // 模拟未捕获绑定(或旧会话)的 seat。
      final session = AppSession(
        sessionId: 'sess-ui',
        workspaceId: 'ws-1',
        folders: const [WorkspaceFolder(path: '/work/project')],
        cli: CliTool.opencode,
        createdAt: 1,
        updatedAt: 1,
      );
      final ctx = launchContextFor(session);
      final loader = buildLoader();

      final first = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(locator.calls, 0, reason: '首屏 page-first');
      expect(first.messages, hasLength(2));
      await warmFullIndex(loader, session);
      expect(locator.calls, 0);

      // task 子会话创建并写入:time_updated 最新 → 旧实现把"最新会话"
      // 解析成子会话,指纹/重读全落在子会话上。
      writer.execute(
        'INSERT INTO session (id, time_created, time_updated) VALUES (?, ?, ?)',
        ['ses_2', 9000, 9000],
      );
      writer.execute(
        'INSERT INTO message (id, session_id, data, time_created, time_updated) '
        'VALUES (?, ?, ?, ?, ?)',
        [
          10,
          'ses_2',
          jsonEncode({'role': 'assistant', 'time': {'created': 9000}}),
          9000,
          9000,
        ],
      );
      writer.execute(
        'INSERT INTO part (id, session_id, message_id, data, time_created, '
        'time_updated) VALUES (?, ?, ?, ?, ?, ?)',
        [
          10,
          'ses_2',
          10,
          jsonEncode({'type': 'text', 'text': 'task output'}),
          9000,
          9000,
        ],
      );
      // 同时 seat 会话自己新增一条消息。
      insertMessage(id: 5, role: 'assistant', created: 5000);
      insertPart(id: 5, messageId: 5, text: 'seat grow', created: 5000);

      final second = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(
        locator.calls,
        0,
        reason: '子会话变成最新会话不得触发全量回退(旧实现每轮重复解析)',
      );
      expect(
        second.messages.any(
          (m) =>
              m.parts.any((p) => p is AiTextPart && p.text == 'seat grow'),
        ),
        isTrue,
        reason: 'seat 会话的新消息必须出现',
      );
      expect(
        second.messages.any(
          (m) =>
              m.parts.any((p) => p is AiTextPart && p.text == 'task output'),
        ),
        isFalse,
        reason: '子会话消息不得混入 seat 列表(同内容不同 id = 重复气泡)',
      );
      expect(
        second.messages,
        hasLength(2),
        reason: '相邻 assistant 合并语义与全量 parse 一致',
      );
    });
  });

  group('legacy schema (part without time_updated)', () {
    test('idle reload is ALWAYS full — the silent degradation repro', () async {
      openLegacyDb();
      seedConversation(legacy: true);
      final loader = buildLoader();
      final session = opencodeSession();
      final ctx = launchContextFor(session);

      final first = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(first.messages, hasLength(2));
      expect(locator.calls, 1);
      expect(locator.lastBundle!.hints['source'], 'sqlite');

      // 完全空闲的第二次 load:没有 time_updated 列 →
      // 增量聚合查询抛错(no such column)被吞 → 增量不可用 →
      // loader 每轮都全量 locate + 全量 parse。
      final second = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(
        locator.calls,
        2,
        reason: 'schema 不兼容时增量不可用,永远回退全量',
      );
      expect(
        identical(second.messages, first.messages),
        isFalse,
        reason: '每轮都是全新 parse',
      );
    });
  });

  group('delta fallback', () {
    test('message deletion (compaction) forces a full reload', () async {
      openModernDb();
      seedConversation();
      final loader = buildLoader();
      final session = opencodeSession();
      final ctx = launchContextFor(session);

      final first = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(first.messages, hasLength(2));
      expect(locator.calls, 0, reason: '首屏 page-first');
      await warmFullIndex(loader, session);
      expect(locator.calls, 0);

      // 压缩:删除一条 message(连同其 part)后新增一条。
      writer.execute('DELETE FROM part WHERE message_id = 2');
      writer.execute('DELETE FROM message WHERE id = 2');
      insertMessage(id: 4, role: 'assistant', created: 4000);
      insertPart(id: 4, messageId: 4, text: 'compact', created: 4000);

      final second = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(
        locator.calls,
        1,
        reason: '删除无法用增量表达 → 回退全量重建',
      );
      expect(
        second.messages.any(
          (m) => m.parts.any(
            (p) => p is AiTextPart && p.text.contains('compact'),
          ),
        ),
        isTrue,
      );
      expect(
        second.messages.any(
          (m) => m.parts.any((p) => p is AiTextPart && p.text == 'hello'),
        ),
        isFalse,
        reason: '被删除的消息必须消失',
      );

      // 重建后增量重新可用:再写一次 → 纯增量。
      insertMessage(id: 5, role: 'user', created: 5000);
      insertPart(id: 5, messageId: 5, text: 'again', created: 5000);
      final third = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(locator.calls, 1, reason: '重建后回到增量路径,不再全量');
      expect(
        identical(third.messages, second.messages),
        isFalse,
        reason: '增量 tick 返回新 List 实例,seat 才能感知变化',
      );
      expect(
        identical(third.messages[0], second.messages[0]),
        isTrue,
        reason: '未变化消息保持实例身份',
      );
      expect(
        third.messages.any(
          (m) => m.parts.any(
            (p) => p is AiTextPart && p.text == 'again',
          ),
        ),
        isTrue,
      );
    });

    test('coalescing preserved: new assistant adjacent to assistant merges',
        () async {
      openModernDb();
      seedConversation();
      final loader = buildLoader();
      final session = opencodeSession();
      final ctx = launchContextFor(session);

      final first = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(first.messages, hasLength(2)); // user + assistant
      expect(locator.calls, 0, reason: '首屏 page-first');
      final baseline = await warmFullIndex(loader, session);
      expect(locator.calls, 0);

      // 流式分片:第二条 assistant 消息紧邻上一条(全量 parse 会合并)。
      insertMessage(id: 3, role: 'assistant', created: 3000);
      insertPart(id: 3, messageId: 3, text: 'chunk2', created: 3000);

      final second = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(locator.calls, 0, reason: '增量路径');
      expect(
        identical(second.messages, baseline.messages),
        isFalse,
        reason: '增量 tick 必须返回新 List 实例,seat 才渲染新消息',
      );
      expect(
        second.messages,
        hasLength(2),
        reason: '相邻 assistant 必须合并成一条(与全量 parse 语义一致)',
      );
      expect(
        (second.messages[1].parts.last as AiTextPart).text,
        'chunk2',
        reason: '合并消息拼接了新分片',
      );
    });
  });
}

class _RecordingLocator extends AiHistoryLocator {
  _RecordingLocator() : super();

  int calls = 0;
  Completer<void>? locateGate;
  SessionHistoryContext? lastCtx;
  AiTranscriptBundle? lastBundle;
  final List<AiTranscriptBundle> bundles = [];

  @override
  Future<AiTranscriptBundle?> locate({
    required SessionHistoryContext ctx,
    required CliTool cli,
  }) async {
    final gate = locateGate;
    if (gate != null) await gate.future;
    calls++;
    lastCtx = ctx;
    final bundle = await super.locate(ctx: ctx, cli: cli);
    lastBundle = bundle;
    if (bundle != null) bundles.add(bundle);
    return bundle;
  }
}
