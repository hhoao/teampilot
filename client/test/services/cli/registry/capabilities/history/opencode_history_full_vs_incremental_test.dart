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
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
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
/// 行为(实现于 OpencodeHistoryIncrementalRefresher):
///  - 首次 load = 全量 locate + parse,随后 seed 指纹对齐;
///  - store 变动后 = DB 行级增量:只重读指纹变化的行,原地合并进同一
///    List 实例,不再全量 locate / 全量 parse;
///  - 删除/压缩/schema 不兼容 = 回退全量。
///
/// 判别信号:
///  - locate 调用次数:增量后保持 1(不再全量 locate);
///  - `identical(messages)`:增量原地合并,跨 refresh 复用同一 List 实例;
///  - bundle hints:首次全量 locate 的 bundle 无 `incremental` 键。
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

  tearDown(() {
    try {
      writer.close();
    } on Object {
      // already closed
    }
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
      expect(locator.calls, 1, reason: '首次 load 必然全量 locate');
      expect(locator.lastCtx?.env['OPENCODE_DB'], dbPath);
      final firstBundle = locator.lastBundle!;
      expect(firstBundle.hints['source'], 'sqlite');
      expect(
        firstBundle.hints['incremental'],
        isNull,
        reason: 'loader 不会走 locateOpencodeTranscriptIncremental',
      );

      // 聊天界面空闲轮询:store 级 token 未变 → 缓存命中,零 locate。
      final second = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(locator.calls, 1, reason: '未变化时连 locate 都不进');
      expect(
        identical(second.messages, first.messages),
        isTrue,
        reason: '缓存命中必须复用同一 List 实例',
      );

      // seat 级 _parentBundles memo:直接 locate 两次,指纹未变 → 同一实例。
      final b1 = await locator.locate(
        ctx: locator.lastCtx!,
        cli: CliTool.opencode,
      );
      final b2 = await locator.locate(
        ctx: locator.lastCtx!,
        cli: CliTool.opencode,
      );
      expect(
        identical(b1, b2),
        isTrue,
        reason: 'seat 指纹未变时 parentBundles memo 直接命中,不重跑 SQL',
      );
    });

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
      expect(locator.calls, 1);

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
      expect(locator.calls, 1, reason: 'store 动了 → 走 DB 行级增量,不再全量 locate');
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
        identical(second.messages, first.messages),
        isTrue,
        reason: '增量路径原地合并,复用同一 List 实例(全量路径才是新实例)',
      );
      expect(
        locator.lastBundle!.hints['source'],
        'sqlite',
        reason: '首次 load 仍是全量 locate(增量从第二次 load 开始)',
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
      expect(locator.calls, 1);

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
      expect(locator.calls, 1, reason: '原地增长 → 行级增量,不再全量 locate');
      expect(
        second.messages.any(
          (m) => m.parts.any(
            (p) => p is AiTextPart && p.text.contains('hello grow'),
          ),
        ),
        isTrue,
      );
      expect(
        identical(second.messages, first.messages),
        isTrue,
        reason: '增量原地替换消息,复用同一 List 实例',
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
      expect(locator.calls, 1);

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
        2,
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
      expect(locator.calls, 2, reason: '重建后回到增量路径,不再全量');
      expect(
        identical(third.messages, second.messages),
        isTrue,
        reason: '增量原地合并,同一 List 实例',
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
      expect(locator.calls, 1);

      // 流式分片:第二条 assistant 消息紧邻上一条(全量 parse 会合并)。
      insertMessage(id: 3, role: 'assistant', created: 3000);
      insertPart(id: 3, messageId: 3, text: 'chunk2', created: 3000);

      final second = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(locator.calls, 1, reason: '增量路径');
      expect(
        identical(second.messages, first.messages),
        isTrue,
        reason: '原地合并复用同一列表实例',
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
  SessionHistoryContext? lastCtx;
  AiTranscriptBundle? lastBundle;
  final List<AiTranscriptBundle> bundles = [];

  @override
  Future<AiTranscriptBundle?> locate({
    required SessionHistoryContext ctx,
    required CliTool cli,
  }) async {
    calls++;
    lastCtx = ctx;
    final bundle = await super.locate(ctx: ctx, cli: cli);
    lastBundle = bundle;
    if (bundle != null) bundles.add(bundle);
    return bundle;
  }
}
