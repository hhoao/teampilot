import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/codex/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/cursor/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/opencode/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/opencode/capabilities/sqlite_worker_pool.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/session_history_context.dart';

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

  test('paged output retains each CLI adapter fixture semantics', () async {
    final fixtures = await _fixtures(base, fs);
    for (final fixture in fixtures) {
      final bundle = await fixture.capability.locate(fixture.context);
      expect(bundle, isNotNull, reason: '${fixture.cli} must locate fixture');
      final full = await fixture.capability.adapter.parse(bundle!);
      final page = await fixture.capability.pageReader!.readLatest(
        ctx: fixture.context,
        limit: 100,
      );

      if (page == null) {
        // A JSONL suffix needing fallback IDs is intentionally unsafe to page;
        // the full adapter remains the exact fallback.
        expect(full, isNotEmpty, reason: '${fixture.cli} full fallback');
        continue;
      }
      expect(
        sameMessageListContent(page.messages, full),
        isTrue,
        reason: '${fixture.cli} page must equal full adapter output',
      );
      expect(page.messages.map((m) => m.id), full.map((m) => m.id));
    }
  });
}

typedef _Fixture = ({
  CliTool cli,
  AiHistoryCapability capability,
  SessionHistoryContext context,
});

Future<List<_Fixture>> _fixtures(Directory base, LocalFilesystem fs) async {
  Future<void> copy(String source, String destination) async {
    final file = File(destination);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(await File(source).readAsBytes());
  }

  final claude = p.join(base.path, 'claude');
  final flashskyai = p.join(base.path, 'flashskyai');
  final codex = p.join(base.path, 'codex');
  final cursor = p.join(base.path, 'cursor');
  final opencode = p.join(base.path, 'opencode');
  await copy(
    'test/fixtures/session_history/claude/basic.jsonl',
    p.join(claude, 'projects', 'bucket', 'task-1.jsonl'),
  );
  await copy(
    'test/fixtures/session_history/flashskyai/basic.jsonl',
    p.join(flashskyai, 'projects', 'bucket', 'task-1.jsonl'),
  );
  await copy(
    'test/fixtures/session_history/codex/basic.jsonl',
    p.join(
      codex,
      'sessions',
      '2026',
      '07',
      '10',
      'rollout-2026-07-10T12-00-00-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl',
    ),
  );
  await copy(
    'test/fixtures/session_history/cursor/agent_transcript_no_tool_id.jsonl',
    p.join(
      cursor,
      'projects',
      'project',
      'agent-transcripts',
      'chat-1',
      'chat-1.jsonl',
    ),
  );
  await _writeOpencodeDb(p.join(opencode, 'opencode.db'));

  return [
    (
      cli: CliTool.claude,
      capability: ClaudeAiHistoryCapability(pageFilesystem: fs),
      context: SessionHistoryContext(
        fs: fs,
        taskId: 'task-1',
        env: const {},
        transcriptRoots: [claude],
        bucket: 'bucket',
      ),
    ),
    (
      cli: CliTool.flashskyai,
      capability: FlashskyaiAiHistoryCapability(pageFilesystem: fs),
      context: SessionHistoryContext(
        fs: fs,
        taskId: 'task-1',
        env: const {},
        transcriptRoots: [flashskyai],
        bucket: 'bucket',
      ),
    ),
    (
      cli: CliTool.codex,
      capability: CodexAiHistoryCapability(pageFilesystem: fs),
      context: SessionHistoryContext(
        fs: fs,
        taskId: 'task-1',
        env: {'CODEX_HOME': codex},
        transcriptRoots: const [],
        bucket: '',
      ),
    ),
    (
      cli: CliTool.cursor,
      capability: CursorAiHistoryCapability(pageFilesystem: fs),
      context: SessionHistoryContext(
        fs: fs,
        taskId: 'task-1',
        env: {'CURSOR_CONFIG_DIR': cursor},
        transcriptRoots: const [],
        bucket: '',
        persistedNativeId: 'chat-1',
      ),
    ),
    (
      cli: CliTool.opencode,
      capability: const OpencodeAiHistoryCapability(),
      context: SessionHistoryContext(
        fs: fs,
        taskId: 'task-1',
        env: {'OPENCODE_DB': p.join(opencode, 'opencode.db')},
        transcriptRoots: const [],
        bucket: '',
        persistedNativeId: 'ses_1',
      ),
    ),
  ];
}

Future<void> _writeOpencodeDb(String path) async {
  await File(path).parent.create(recursive: true);
  final db = sqlite3.open(path);
  try {
    db.execute('''
CREATE TABLE session (id TEXT PRIMARY KEY, parent_id TEXT, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL);
CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, data TEXT NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL);
CREATE TABLE part (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, message_id TEXT NOT NULL, data TEXT NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL);
''');
    db.execute('INSERT INTO session VALUES (?, ?, ?, ?)', [
      'ses_1',
      null,
      1001,
      1001,
    ]);
    db.execute('INSERT INTO message VALUES (?, ?, ?, ?, ?)', [
      'msg_user',
      'ses_1',
      '{"role":"user","time":{"created":1001}}',
      1001,
      1001,
    ]);
    db.execute('INSERT INTO message VALUES (?, ?, ?, ?, ?)', [
      'msg_assistant',
      'ses_1',
      '{"role":"assistant","time":{"created":2001}}',
      2001,
      2001,
    ]);
    db.execute('INSERT INTO part VALUES (?, ?, ?, ?, ?, ?)', [
      'part_user',
      'ses_1',
      'msg_user',
      '{"type":"text","text":"hi"}',
      1001,
      1001,
    ]);
    db.execute('INSERT INTO part VALUES (?, ?, ?, ?, ?, ?)', [
      'part_assistant',
      'ses_1',
      'msg_assistant',
      '{"type":"text","text":"hello"}',
      2001,
      2001,
    ]);
  } finally {
    db.dispose();
  }
}
