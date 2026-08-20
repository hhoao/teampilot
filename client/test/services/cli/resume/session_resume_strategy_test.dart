import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/codex/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/cursor/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/cli/opencode/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/opencode/capabilities/sqlite_worker_pool.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/cursor_warm_tier_manifest_paths.dart';

void main() {
  late Directory base;
  final fs = LocalFilesystem();

  setUp(() async {
    base = await Directory.systemTemp.createTemp('resume_strategy_');
  });
  tearDown(() async {
    await OpencodeSqliteWorkerPool.instance.disposeAllAndWait();
    if (await base.exists()) await base.delete(recursive: true);
  });

  ResumeContext ctx({
    Map<String, String> env = const {},
    List<String> transcriptRoots = const [],
    String bucket = '',
    String taskId = 'task-1',
    String? persistedNativeId,
    String? workspaceId,
    String? sessionId,
    String? memberId,
    String? teamId,
    String? manifestDataRoot,
  }) {
    return ResumeContext(
      fs: fs,
      toolValue: 'x',
      taskId: taskId,
      env: env,
      transcriptRoots: transcriptRoots,
      bucket: bucket,
      persistedNativeId: persistedNativeId,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: memberId,
      teamId: teamId,
      manifestDataRoot: manifestDataRoot,
    );
  }

  group('CodexResumeStrategy', () {
    test('captures the rollout uuid from the isolated CODEX_HOME', () async {
      const id = '7f9f9a2e-1b3c-4c7a-9b0e-0123456789ab';
      final dir = p.join(base.path, 'sessions', '2026', '06', '17');
      await Directory(dir).create(recursive: true);
      await File(
        p.join(dir, 'rollout-2026-06-17T10-00-00-$id.jsonl'),
      ).writeAsString('{}');

      final got = await const CodexAiHistoryCapability().detectNativeId(
        ctx(env: {'CODEX_HOME': base.path}),
      );
      expect(got, id);
    });

    test('persisted id wins without scanning', () async {
      final got = await const CodexAiHistoryCapability().detectNativeId(
        ctx(env: {'CODEX_HOME': base.path}, persistedNativeId: 'kept'),
      );
      expect(got, 'kept');
    });

    test('returns null when nothing is stored', () async {
      final got = await const CodexAiHistoryCapability().detectNativeId(
        ctx(env: {'CODEX_HOME': base.path}),
      );
      expect(got, isNull);
    });
  });

  group('OpencodeResumeStrategy', () {
    test('captures ses_ id from opencode.db', () async {
      final dbPath = p.join(base.path, 'opencode.db');
      final db = sqlite3.open(dbPath);
      db.execute('''
CREATE TABLE session (
  id TEXT PRIMARY KEY,
  parent_id TEXT,
  time_updated INTEGER,
  data TEXT
);
''');
      db.execute(
        "INSERT INTO session(id, parent_id, time_updated) VALUES ('ses_old', NULL, 1)",
      );
      db.execute(
        "INSERT INTO session(id, parent_id, time_updated) VALUES ('ses_new', NULL, 2)",
      );
      db.dispose();

      final got = await const OpencodeAiHistoryCapability().detectNativeId(
        ctx(env: {'OPENCODE_DB': dbPath}),
      );
      expect(got, 'ses_new');
    });

    test('persisted id wins over sqlite scan', () async {
      final dbPath = p.join(base.path, 'opencode.db');
      final db = sqlite3.open(dbPath);
      db.execute('''
CREATE TABLE session (
  id TEXT PRIMARY KEY,
  time_updated INTEGER
);
''');
      db.execute(
        "INSERT INTO session(id, time_updated) VALUES ('ses_db', 1)",
      );
      db.dispose();

      final got = await const OpencodeAiHistoryCapability().detectNativeId(
        ctx(
          env: {'OPENCODE_DB': dbPath},
          persistedNativeId: 'ses_kept',
        ),
      );
      expect(got, 'ses_kept');
    });
  });

  group('CursorResumeStrategy', () {
    Future<void> writeChat(
      String chatId, {
      required bool hasConversation,
      required int updatedAtMs,
    }) async {
      final dir = p.join(base.path, 'chats', 'wshash', chatId);
      await Directory(dir).create(recursive: true);
      await File(p.join(dir, 'meta.json')).writeAsString(
        '{"schemaVersion":1,"hasConversation":$hasConversation,'
        '"updatedAtMs":$updatedAtMs}',
      );
    }

    test('captures the newest chat that has a real conversation', () async {
      // An empty pre-created chat must be ignored in favor of the real one.
      await writeChat('empty', hasConversation: false, updatedAtMs: 200);
      await writeChat('real-old', hasConversation: true, updatedAtMs: 100);
      await writeChat('real-new', hasConversation: true, updatedAtMs: 150);

      final got = await const CursorAiHistoryCapability().detectNativeId(
        ctx(env: {'CURSOR_CONFIG_DIR': base.path}),
      );
      expect(got, 'real-new');
    });

    test('returns null when only empty chats exist', () async {
      await writeChat('empty', hasConversation: false, updatedAtMs: 200);
      final got = await const CursorAiHistoryCapability().detectNativeId(
        ctx(env: {'CURSOR_CONFIG_DIR': base.path}),
      );
      expect(got, isNull);
    });

    test('returns null when there is no chats dir', () async {
      final got = await const CursorAiHistoryCapability().detectNativeId(
        ctx(env: {'CURSOR_CONFIG_DIR': base.path}),
      );
      expect(got, isNull);
    });

    test(
      'mixed mode scans HOME/.cursor/chats when CURSOR_CONFIG_DIR unset',
      () async {
        final home = p.join(base.path, 'member-home');
        final configDir = p.join(home, '.cursor');
        final dir = p.join(configDir, 'chats', 'wshash', 'mixed-chat');
        await Directory(dir).create(recursive: true);
        await File(p.join(dir, 'meta.json')).writeAsString(
          '{"schemaVersion":1,"hasConversation":true,"updatedAtMs":300}',
        );

        final got = await const CursorAiHistoryCapability().detectNativeId(
          ctx(env: {'HOME': home, 'USERPROFILE': home}),
        );
        expect(got, 'mixed-chat');
      },
    );

    test('persistedNativeId wins over scanned chats', () async {
      await writeChat('scanned-chat', hasConversation: true, updatedAtMs: 300);
      final got = await const CursorAiHistoryCapability().detectNativeId(
        ctx(
          env: {'CURSOR_CONFIG_DIR': base.path},
          persistedNativeId: 'kept-chat',
        ),
      );
      expect(got, 'kept-chat');
    });

    test('workspace manifest chatId does not resume a different session', () async {
      final home = p.join(base.path, 'member-home');
      await Directory(p.join(home, '.cursor')).create(recursive: true);

      final layout = RuntimeLayout(teampilotRoot: base.path, fs: fs);
      final manifestPath = layout.workspaceLifecycleManifestPath(
        'ws',
        cursorTestTeamId,
        'cursor',
      );
      await Directory(p.dirname(manifestPath)).create(recursive: true);
      await File(manifestPath).writeAsString(
        '{"schemaVersion":4,"tool":"cursor","workspaceId":"ws","teamId":"$cursorTestTeamId",'
        '"workspacePathHash":"slug","workspaceSlug":"slug","phase":"ready",'
        '"shared":{"root":"runtime/teams/$cursorTestTeamId/cursor",'
        '"projectsDir":"runtime/teams/$cursorTestTeamId/cursor/projects/slug",'
        '"cliConfigBase":"runtime/teams/$cursorTestTeamId/cursor/cli-config.base.json",'
        '"pluginsLocalDir":"runtime/teams/$cursorTestTeamId/cursor/plugins/local",'
        '"skillsCursorDir":"runtime/teams/$cursorTestTeamId/cursor/skills-cursor",'
        '"mcpBase":"runtime/teams/$cursorTestTeamId/cursor/mcp.base.json",'
        '"settingsJson":"runtime/teams/$cursorTestTeamId/cursor/settings.json"},'
        '"members":{"team-lead":{"homeRoot":"runtime/teams/$cursorTestTeamId/team-lead/cursor/home",'
        '"chatId":"manifest-chat"}},"sessionOverlays":{}}',
      );

      final got = await const CursorAiHistoryCapability().detectNativeId(
        ctx(
          env: {'HOME': home, 'USERPROFILE': home},
          workspaceId: 'ws',
          sessionId: 'new-sess',
          memberId: 'team-lead',
          teamId: cursorTestTeamId,
          manifestDataRoot: base.path,
        ),
      );
      expect(got, isNull);
    });
  });

  group('ClaudeResumeStrategy', () {
    test('detects transcript under projects/{bucket}/', () async {
      final projects = p.join(base.path, 'projects', 'home-me-proj');
      await Directory(projects).create(recursive: true);
      await File(p.join(projects, 'task-1.jsonl')).writeAsString('{}');

      final got = await const ClaudeAiHistoryCapability().detectNativeId(
        ctx(transcriptRoots: [base.path], bucket: 'home-me-proj'),
      );
      expect(got, 'task-1');
    });

    test('ignores flashskyai workspaces layout', () async {
      final workspaces = p.join(base.path, 'workspaces', 'home-me-proj');
      await Directory(workspaces).create(recursive: true);
      await File(p.join(workspaces, 'task-1.jsonl')).writeAsString('{}');

      final got = await const ClaudeAiHistoryCapability().detectNativeId(
        ctx(transcriptRoots: [base.path], bucket: 'home-me-proj'),
      );
      expect(got, isNull);
    });

    test('returns null when no transcript exists', () async {
      final got = await const ClaudeAiHistoryCapability().detectNativeId(
        ctx(transcriptRoots: [base.path], bucket: 'home-me-proj'),
      );
      expect(got, isNull);
    });
  });

  group('TranscriptResumeStrategy', () {
    test('detects the pinned transcript file and returns the taskId', () async {
      final workspaces = p.join(base.path, 'workspaces', 'home-me-proj');
      await Directory(workspaces).create(recursive: true);
      await File(p.join(workspaces, 'task-1.jsonl')).writeAsString('{}');

      final got = await const FlashskyaiAiHistoryCapability().detectNativeId(
        ctx(transcriptRoots: [base.path], bucket: 'home-me-proj'),
      );
      expect(got, 'task-1');
    });

    test('detects transcript under projects (real flashskyai layout)', () async {
      final projects = p.join(base.path, 'projects', 'home-me-proj');
      await Directory(projects).create(recursive: true);
      await File(p.join(projects, 'task-1.jsonl')).writeAsString('{}');

      final got = await const FlashskyaiAiHistoryCapability().detectNativeId(
        ctx(transcriptRoots: [base.path], bucket: 'home-me-proj'),
      );
      expect(got, 'task-1');
    });

    test('returns null when no transcript exists', () async {
      final got = await const FlashskyaiAiHistoryCapability().detectNativeId(
        ctx(transcriptRoots: [base.path], bucket: 'home-me-proj'),
      );
      expect(got, isNull);
    });
  });
}
