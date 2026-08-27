import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/codex/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/cursor/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/cursor/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/opencode/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/opencode/capabilities/sqlite_worker_pool.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/jsonl_transcript_page_reader.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../../../../support/in_memory_filesystem.dart';

/// Capability-level guard: every launch CLI must opt into paged history.
/// When a reader cannot prove a page safe, it returns null and the loader
/// retains the existing full adapter parse as the correctness fallback.
void main() {
  late Directory base;
  final fs = LocalFilesystem();

  setUp(() async => base = await Directory.systemTemp.createTemp('page_eq_'));
  tearDown(() async {
    await OpencodeSqliteWorkerPool.instance.disposeAllAndWait();
    if (await base.exists()) await base.delete(recursive: true);
  });

  test(
    'launch CLIs expose a paged transcript reader with full-parse fallback',
    () {
      final registry = CliToolRegistry.builtIn();

      for (final cli in [
        CliTool.claude,
        CliTool.codex,
        CliTool.cursor,
        CliTool.flashskyai,
        CliTool.opencode,
      ]) {
        final history = registry.capability<AiHistoryCapability>(cli);
        expect(history, isNotNull, reason: '$cli must expose history');
        expect(
          history!.pageReader,
          isNotNull,
          reason:
              '$cli must expose a reader; null page results use adapter.parse',
        );
      }
    },
  );

  test('JSONL paging reads through ctx.fs, not AppStorage.fs', () async {
    final homeRoot = await Directory.systemTemp.createTemp('page_home_fs_');
    addTearDown(() async {
      AppStorage.resetForTesting();
      AppPathsBootstrapper.resetForTesting();
      if (await homeRoot.exists()) await homeRoot.delete(recursive: true);
    });
    AppStorage.installForTesting(
      filesystem: InMemoryFilesystem(),
      paths: AppPaths(homeRoot.path),
      home: homeRoot.path,
      cwd: homeRoot.path,
    );

    final workRoot = p.join(base.path, 'ctx-fs-claude');
    await File(
      p.join(workRoot, 'projects', 'bucket', 'task-1.jsonl'),
    ).parent.create(recursive: true);
    await File(
      p.join(workRoot, 'projects', 'bucket', 'task-1.jsonl'),
    ).writeAsBytes(
      await File(
        'test/fixtures/session_history/claude/basic.jsonl',
      ).readAsBytes(),
    );

    const capability = ClaudeAiHistoryCapability();
    final ctx = SessionHistoryContext(
      fs: fs,
      taskId: 'task-1',
      env: const {},
      transcriptRoots: [workRoot],
      bucket: 'bucket',
    );

    final bundle = await capability.locate(ctx);
    expect(bundle, isNotNull, reason: 'locator already uses ctx.fs');
    final full = await capability.adapter.parse(bundle!);
    expect(full, isNotEmpty);

    final page = await capability.pageReader.readLatest(ctx: ctx, limit: 100);
    expect(
      page,
      isNotNull,
      reason: 'production paging must stat/read via ctx.fs, not AppStorage.fs',
    );
    expect(sameMessageListContent(page!.messages, full), isTrue);
    expect(page.messages.map((m) => m.id), full.map((m) => m.id));
  });

  test(
    'concatenated pages match adapter output for existing fixture families',
    () async {
      final fixtures = await _comparableFamilies(base, fs);
      expect(fixtures, isNotEmpty);
      for (final fixture in fixtures) {
        final bundle = await fixture.capability.locate(fixture.context);
        expect(
          bundle,
          isNotNull,
          reason: '${fixture.label} must locate fixture',
        );
        final full = await fixture.capability.adapter.parse(bundle!);
        expect(full, isNotEmpty, reason: '${fixture.label} adapter output');
        final paged = await _concatenatedPages(
          fixture.capability.pageReader!,
          fixture.context,
          limit: fixture.pageLimit,
          label: fixture.label,
        );
        expect(
          sameMessageListContent(paged, full),
          isTrue,
          reason: '${fixture.label} concatenated pages must equal adapter',
        );
        expect(
          paged.map((m) => m.id),
          full.map((m) => m.id),
          reason: '${fixture.label} message ids must match',
        );
      }
    },
  );

  test(
    'no-id Cursor suffix window returns null rather than guessing tool ids',
    () async {
      final fixture = await _cursorNoIdFixture(base, fs);
      final path = await locateCursorTranscriptPath(fixture.context);
      expect(path, isNotNull);
      final size = (await fs.stat(path!)).size ?? 0;
      expect(size, greaterThan(300));
      final reader = JsonlTranscriptPageReader(
        fs: fs,
        lineAppend: appendCursorJsonlEvent,
        fallbackPrefix: 'cursor',
        sourcePath: (_) async => path,
        windowSizes: const [150],
      );
      expect(
        await reader.readLatest(ctx: fixture.context, limit: 100),
        isNull,
        reason: 'unsafe no-id suffix must not invent a page',
      );
    },
  );

  test('OpenCode paging returns null without a stable store token', () async {
    final dataDir = p.join(base.path, 'oc-no-token');
    await _writeOpencodeDb(
      p.join(dataDir, 'opencode.db'),
      includeTimeUpdated: false,
    );
    const capability = OpencodeAiHistoryCapability();
    final ctx = SessionHistoryContext(
      fs: fs,
      taskId: 'task-1',
      env: {'OPENCODE_DB': p.join(dataDir, 'opencode.db')},
      transcriptRoots: const [],
      bucket: '',
      persistedNativeId: 'ses_1',
    );
    expect(await capability.liveCacheToken(ctx), isNull);
    expect(await capability.pageReader.readLatest(ctx: ctx, limit: 1), isNull);
  });

  test('OpenCode readOlder returns null for a mutated sourceToken', () async {
    final dataDir = p.join(base.path, 'oc-mutated-token');
    await _writeOpencodeDb(p.join(dataDir, 'opencode.db'), extraTurns: 2);
    const capability = OpencodeAiHistoryCapability();
    final ctx = SessionHistoryContext(
      fs: fs,
      taskId: 'task-1',
      env: {'OPENCODE_DB': p.join(dataDir, 'opencode.db')},
      transcriptRoots: const [],
      bucket: '',
      persistedNativeId: 'ses_1',
    );
    final latest = await capability.pageReader.readLatest(ctx: ctx, limit: 1);
    expect(latest, isNotNull);
    expect(latest!.nextCursor, isNotNull);
    final mutated = AiHistoryCursor(
      sourceToken: '${latest.nextCursor!.sourceToken}x',
      offset: latest.nextCursor!.offset,
      lineHash: latest.nextCursor!.lineHash,
    );
    expect(
      await capability.pageReader.readOlder(
        ctx: ctx,
        cursor: mutated,
        limit: 1,
      ),
      isNull,
    );
  });

  test('OpenCode readOlder returns null for a mismatched lineHash', () async {
    final dataDir = p.join(base.path, 'oc-bad-hash');
    await _writeOpencodeDb(p.join(dataDir, 'opencode.db'), extraTurns: 2);
    const capability = OpencodeAiHistoryCapability();
    final ctx = SessionHistoryContext(
      fs: fs,
      taskId: 'task-1',
      env: {'OPENCODE_DB': p.join(dataDir, 'opencode.db')},
      transcriptRoots: const [],
      bucket: '',
      persistedNativeId: 'ses_1',
    );
    final latest = await capability.pageReader.readLatest(ctx: ctx, limit: 1);
    expect(latest, isNotNull);
    expect(latest!.nextCursor, isNotNull);
    final mismatched = AiHistoryCursor(
      sourceToken: latest.nextCursor!.sourceToken,
      offset: latest.nextCursor!.offset,
      lineHash: latest.nextCursor!.lineHash ^ 0xFFFFFFFF,
    );
    expect(
      await capability.pageReader.readOlder(
        ctx: ctx,
        cursor: mismatched,
        limit: 1,
      ),
      isNull,
    );
  });
}

typedef _Fixture = ({
  String label,
  AiHistoryCapability capability,
  SessionHistoryContext context,
  int pageLimit,
});

Future<List<AiMessage>> _concatenatedPages(
  AiTranscriptPageReader reader,
  SessionHistoryContext ctx, {
  required int limit,
  required String label,
}) async {
  final latest = await reader.readLatest(ctx: ctx, limit: limit);
  expect(latest, isNotNull, reason: '$label latest page');
  final messages = [...latest!.messages];
  var cursor = latest.nextCursor;
  var guard = 0;
  while (cursor != null) {
    expect(guard++, lessThan(64));
    final older = await reader.readOlder(
      ctx: ctx,
      cursor: cursor,
      limit: limit,
    );
    expect(older, isNotNull, reason: '$label older page');
    messages.insertAll(0, older!.messages);
    cursor = older.nextCursor;
  }
  return messages;
}

Future<List<_Fixture>> _comparableFamilies(
  Directory base,
  LocalFilesystem fs,
) async {
  return [
    await _claudeFamily(base, fs, 'basic.jsonl'),
    await _claudeFamily(base, fs, 'streamed_turn.jsonl'),
    await _claudeFamily(base, fs, 'truncated_bash.jsonl'),
    await _flashskyaiFamily(base, fs, 'basic.jsonl'),
    await _flashskyaiFamily(base, fs, 'streamed_tools.jsonl'),
    await _flashskyaiFamily(base, fs, 'edit_real.jsonl'),
    await _codexFamily(
      base,
      fs,
      'reasoning_and_tools.jsonl',
      '11111111-1111-1111-1111-111111111111',
    ),
    await _codexFamily(
      base,
      fs,
      'custom_tool_call_dual_form.jsonl',
      '22222222-2222-2222-2222-222222222222',
    ),
    await _codexFamily(
      base,
      fs,
      'response_item_messages.jsonl',
      '33333333-3333-3333-3333-333333333333',
    ),
    await _cursorProjectFamily(base, fs, 'chat-aaaa-bbbb-cccc-dddd'),
    await _cursorProjectFamily(base, fs, 'chat-strreplace-write'),
    await _cursorProjectFamily(base, fs, 'chat-shell-missing-result'),
    await _opencodeStorageFamily(
      base,
      fs,
      label: 'opencode/storage',
      storageRoot: 'test/fixtures/session_history/opencode/storage',
      sessionId: 'ses_demo001',
    ),
    await _opencodeStorageFamily(
      base,
      fs,
      label: 'opencode/from_db_shape',
      storageRoot:
          'test/fixtures/session_history/opencode/from_db_shape/storage',
      sessionId: 'ses_dbdemo001',
    ),
  ];
}

Future<_Fixture> _claudeFamily(
  Directory base,
  LocalFilesystem fs,
  String name,
) async {
  final root = p.join(base.path, 'claude-$name');
  await _copyFile(
    'test/fixtures/session_history/claude/$name',
    p.join(root, 'projects', 'bucket', 'task-1.jsonl'),
  );
  return (
    label: 'claude/$name',
    capability: ClaudeAiHistoryCapability(pageFilesystem: fs),
    context: SessionHistoryContext(
      fs: fs,
      taskId: 'task-1',
      env: const {},
      transcriptRoots: [root],
      bucket: 'bucket',
    ),
    pageLimit: 1,
  );
}

Future<_Fixture> _flashskyaiFamily(
  Directory base,
  LocalFilesystem fs,
  String name,
) async {
  final root = p.join(base.path, 'flashskyai-$name');
  await _copyFile(
    'test/fixtures/session_history/flashskyai/$name',
    p.join(root, 'projects', 'bucket', 'task-1.jsonl'),
  );
  return (
    label: 'flashskyai/$name',
    capability: FlashskyaiAiHistoryCapability(pageFilesystem: fs),
    context: SessionHistoryContext(
      fs: fs,
      taskId: 'task-1',
      env: const {},
      transcriptRoots: [root],
      bucket: 'bucket',
    ),
    pageLimit: 1,
  );
}

Future<_Fixture> _codexFamily(
  Directory base,
  LocalFilesystem fs,
  String name,
  String uuid,
) async {
  final root = p.join(base.path, 'codex-$name');
  await _copyFile(
    'test/fixtures/session_history/codex/$name',
    p.join(
      root,
      'sessions',
      '2026',
      '07',
      '10',
      'rollout-2026-07-10T12-00-00-$uuid.jsonl',
    ),
  );
  return (
    label: 'codex/$name',
    capability: CodexAiHistoryCapability(pageFilesystem: fs),
    context: SessionHistoryContext(
      fs: fs,
      taskId: 'task-1',
      env: {'CODEX_HOME': root},
      transcriptRoots: const [],
      bucket: '',
    ),
    pageLimit: 100,
  );
}

Future<_Fixture> _cursorProjectFamily(
  Directory base,
  LocalFilesystem fs,
  String chatId,
) async {
  final root = p.join(base.path, 'cursor-$chatId');
  await _copyCursorProjectTree(root);
  return (
    label: 'cursor/$chatId',
    capability: CursorAiHistoryCapability(pageFilesystem: fs),
    context: SessionHistoryContext(
      fs: fs,
      taskId: 'task-1',
      env: {'CURSOR_CONFIG_DIR': root},
      transcriptRoots: const [],
      bucket: '',
      persistedNativeId: chatId,
    ),
    pageLimit: 100,
  );
}

Future<_Fixture> _cursorNoIdFixture(Directory base, LocalFilesystem fs) async {
  final root = p.join(base.path, 'cursor-no-id');
  await _copyFile(
    'test/fixtures/session_history/cursor/agent_transcript_no_tool_id.jsonl',
    p.join(
      root,
      'projects',
      'project',
      'agent-transcripts',
      'chat-1',
      'chat-1.jsonl',
    ),
  );
  return (
    label: 'cursor/agent_transcript_no_tool_id.jsonl',
    capability: CursorAiHistoryCapability(pageFilesystem: fs),
    context: SessionHistoryContext(
      fs: fs,
      taskId: 'task-1',
      env: {'CURSOR_CONFIG_DIR': root},
      transcriptRoots: const [],
      bucket: '',
      persistedNativeId: 'chat-1',
    ),
    pageLimit: 100,
  );
}

Future<_Fixture> _opencodeStorageFamily(
  Directory base,
  LocalFilesystem fs, {
  required String label,
  required String storageRoot,
  required String sessionId,
}) async {
  final dataDir = p.join(base.path, label.replaceAll('/', '-'));
  await _writeOpencodeDbFromJsonTree(
    p.join(dataDir, 'opencode.db'),
    storageRoot,
  );
  return (
    label: label,
    capability: const OpencodeAiHistoryCapability(),
    context: SessionHistoryContext(
      fs: fs,
      taskId: 'task-1',
      env: {'OPENCODE_DB': p.join(dataDir, 'opencode.db')},
      transcriptRoots: const [],
      bucket: '',
      persistedNativeId: sessionId,
    ),
    pageLimit: 1,
  );
}

Future<void> _copyFile(String source, String destination) async {
  final file = File(destination);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(await File(source).readAsBytes());
}

Future<void> _copyCursorProjectTree(String destination) async {
  final fixtureRoot = Directory('test/fixtures/session_history/cursor');
  await for (final entity in fixtureRoot.list(recursive: true)) {
    if (entity is! File) continue;
    final rel = p.relative(entity.path, from: fixtureRoot.path);
    final dest = File(p.join(destination, rel));
    await dest.parent.create(recursive: true);
    await dest.writeAsBytes(await entity.readAsBytes());
  }
}

Future<void> _writeOpencodeDbFromJsonTree(
  String dbPath,
  String storageRoot,
) async {
  await File(dbPath).parent.create(recursive: true);
  final db = sqlite3.open(dbPath);
  try {
    db.execute('''
CREATE TABLE session (id TEXT PRIMARY KEY, parent_id TEXT, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL);
CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, data TEXT NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL);
CREATE TABLE part (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, message_id TEXT NOT NULL, data TEXT NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL);
''');
    final messagesDir = Directory(p.join(storageRoot, 'message'));
    final partsDir = Directory(p.join(storageRoot, 'part'));
    final sessionIds = <String>{};
    if (await messagesDir.exists()) {
      await for (final entity in messagesDir.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final raw = await entity.readAsString();
        final obj = jsonDecode(raw);
        if (obj is! Map) continue;
        final id = '${obj['id'] ?? p.basenameWithoutExtension(entity.path)}';
        final sessionId = '${obj['sessionID'] ?? ''}';
        if (id.isEmpty || sessionId.isEmpty) continue;
        sessionIds.add(sessionId);
        final created = _jsonTime(Map<Object?, Object?>.from(obj)) ?? 1;
        db.execute('INSERT INTO message VALUES (?, ?, ?, ?, ?)', [
          id,
          sessionId,
          raw,
          created,
          created,
        ]);
      }
    }
    if (await partsDir.exists()) {
      await for (final entity in partsDir.list(recursive: true)) {
        if (entity is! File) continue;
        final raw = await entity.readAsString();
        Map<String, dynamic>? obj;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) obj = Map<String, dynamic>.from(decoded);
        } on Object {
          obj = null;
        }
        final id = obj == null
            ? p.basenameWithoutExtension(entity.path)
            : '${obj['id'] ?? p.basenameWithoutExtension(entity.path)}';
        final messageId = obj == null
            ? p.basename(p.dirname(entity.path))
            : '${obj['messageID'] ?? p.basename(p.dirname(entity.path))}';
        final sessionId = obj == null
            ? sessionIds.first
            : '${obj['sessionID'] ?? sessionIds.first}';
        final created = obj == null
            ? 1
            : (_jsonTime(Map<Object?, Object?>.from(obj)) ?? 1);
        db.execute('INSERT INTO part VALUES (?, ?, ?, ?, ?, ?)', [
          id,
          sessionId,
          messageId,
          raw,
          created,
          created,
        ]);
      }
    }
    for (final sessionId in sessionIds) {
      db.execute('INSERT INTO session VALUES (?, ?, ?, ?)', [
        sessionId,
        null,
        1,
        1,
      ]);
    }
  } finally {
    db.dispose();
  }
}

int? _jsonTime(Map<Object?, Object?> obj) {
  final time = obj['time'];
  if (time is! Map) return null;
  final created = time['created'];
  if (created is int) return created;
  if (created is num) return created.toInt();
  return null;
}

Future<void> _writeOpencodeDb(
  String path, {
  bool includeTimeUpdated = true,
  int extraTurns = 0,
}) async {
  await File(path).parent.create(recursive: true);
  final db = sqlite3.open(path);
  try {
    if (includeTimeUpdated) {
      db.execute('''
CREATE TABLE session (id TEXT PRIMARY KEY, parent_id TEXT, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL);
CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, data TEXT NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL);
CREATE TABLE part (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, message_id TEXT NOT NULL, data TEXT NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL);
''');
    } else {
      db.execute('''
CREATE TABLE session (id TEXT PRIMARY KEY, parent_id TEXT, time_created INTEGER NOT NULL);
CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, data TEXT NOT NULL, time_created INTEGER NOT NULL);
CREATE TABLE part (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, message_id TEXT NOT NULL, data TEXT NOT NULL, time_created INTEGER NOT NULL);
''');
    }
    void insertSession() {
      if (includeTimeUpdated) {
        db.execute('INSERT INTO session VALUES (?, ?, ?, ?)', [
          'ses_1',
          null,
          1001,
          1001,
        ]);
      } else {
        db.execute('INSERT INTO session VALUES (?, ?, ?)', [
          'ses_1',
          null,
          1001,
        ]);
      }
    }

    void insertMessage(String id, String role, int created) {
      final data = '{"role":"$role","time":{"created":$created}}';
      if (includeTimeUpdated) {
        db.execute('INSERT INTO message VALUES (?, ?, ?, ?, ?)', [
          id,
          'ses_1',
          data,
          created,
          created,
        ]);
      } else {
        db.execute('INSERT INTO message VALUES (?, ?, ?, ?)', [
          id,
          'ses_1',
          data,
          created,
        ]);
      }
    }

    void insertPart(String id, String messageId, String text, int created) {
      final data = '{"type":"text","text":"$text"}';
      if (includeTimeUpdated) {
        db.execute('INSERT INTO part VALUES (?, ?, ?, ?, ?, ?)', [
          id,
          'ses_1',
          messageId,
          data,
          created,
          created,
        ]);
      } else {
        db.execute('INSERT INTO part VALUES (?, ?, ?, ?, ?)', [
          id,
          'ses_1',
          messageId,
          data,
          created,
        ]);
      }
    }

    insertSession();
    insertMessage('msg_user', 'user', 1001);
    insertMessage('msg_assistant', 'assistant', 2001);
    insertPart('part_user', 'msg_user', 'hi', 1001);
    insertPart('part_assistant', 'msg_assistant', 'hello', 2001);
    for (var i = 0; i < extraTurns; i++) {
      final created = 3001 + i;
      insertMessage('msg_extra_$i', 'user', created);
      insertPart('part_extra_$i', 'msg_extra_$i', 'extra $i', created);
    }
  } finally {
    db.dispose();
  }
}
