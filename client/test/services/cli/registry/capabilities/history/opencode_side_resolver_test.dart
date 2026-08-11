import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:teampilot/services/cli/opencode/capabilities/history/side_resolver.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/utils/logging/logger_utils.dart';

void main() {
  late Directory base;
  final fs = LocalFilesystem();
  const resolver = OpencodeSideResolver();

  const parentSessionId = 'ses_parent001';
  const childSessionId = 'ses_child001';
  const nestedChildSessionId = 'ses_child002';
  const mismatchedParentId = 'ses_wrong_parent';

  Future<String> _readLogWhenContains(String path, String needle) async {
    final file = File(path);
    for (var attempt = 0; attempt < 40; attempt++) {
      if (await file.exists()) {
        final contents = await file.readAsString();
        if (contents.contains(needle)) return contents;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  Future<void> _ensureFileLogging(Directory logRoot) async {
    if (!AppLogger.instance.getFileLoggerInitialized()) {
      await AppLogger.instance.initFileLogging(logRoot.path);
    }
  }

  Future<void> expectParentIdMismatchLogged({
    required String childId,
    required String expectedParent,
    required String actualParent,
  }) async {
    await AppLogger.instance.flushFileLogging();
    final logPath = AppLogger.instance.currentLogFilePath;
    if (logPath == null) return;

    final contents = await _readLogWhenContains(
      logPath,
      '[subagent-inflate] OpenCode child session parent_id mismatch',
    );
    expect(
      contents,
      contains('[subagent-inflate] OpenCode child session parent_id mismatch'),
    );
    expect(contents, contains('child=$childId'));
    expect(contents, contains('expectedParent=$expectedParent'));
    expect(contents, contains('actualParent=$actualParent'));
  }

  setUp(() async {
    base = await Directory.systemTemp.createTemp('opencode_side_resolver_');
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  SessionHistoryContext ctx({
    required String dataDir,
    String? persistedNativeId,
  }) {
    return SessionHistoryContext(
      fs: fs,
      taskId: 'task-1',
      env: {'OPENCODE_DB': p.join(dataDir, 'opencode.db')},
      transcriptRoots: const [],
      bucket: '',
      persistedNativeId: persistedNativeId,
    );
  }

  Future<void> writeJson(String relativePath, Map<String, Object?> body) async {
    final file = File(p.join(base.path, relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(body));
  }

  Future<void> writeParentWithTaskResult({
    required Object? taskResult,
    String sessionId = parentSessionId,
  }) async {
    await writeJson('storage/session/proj_demo/$sessionId.json', {
      'id': sessionId,
      'projectID': 'proj_demo',
      'title': 'parent',
      'time': {'created': 1},
    });
    await writeJson('storage/message/$sessionId/msg_task.json', {
      'id': 'msg_task',
      'sessionID': sessionId,
      'role': 'assistant',
      'time': {'created': 2},
    });
    await writeJson('storage/part/msg_task/prt_task.json', {
      'id': 'prt_task',
      'messageID': 'msg_task',
      'type': 'tool',
      'tool': 'task',
      'callID': 'call_task_1',
      'state': {
        'status': 'completed',
        'input': {'prompt': 'do work'},
        'output': taskResult,
        'metadata': {},
      },
    });
  }

  Future<void> writeChildSession({
    required String sessionId,
    String? parentId,
    String userText = 'child hello',
  }) async {
    final session = <String, Object?>{
      'id': sessionId,
      'projectID': 'proj_demo',
      'title': 'child',
      'time': {'created': 3},
    };
    if (parentId != null) {
      session['parent_id'] = parentId;
    }
    await writeJson('storage/session/proj_demo/$sessionId.json', session);
    await writeJson('storage/message/$sessionId/msg_child_user.json', {
      'id': 'msg_child_user',
      'sessionID': sessionId,
      'role': 'user',
      'time': {'created': 4},
    });
    await writeJson('storage/part/msg_child_user/prt_child_text.json', {
      'id': 'prt_child_text',
      'messageID': 'msg_child_user',
      'type': 'text',
      'text': userText,
    });
  }

  AiToolCallPart taskPart({Object? result}) {
    return AiToolCallPart(
      toolCallId: 'call_task_1',
      toolName: 'task',
      args: const {'prompt': 'do work'},
      result: result,
      status: AiToolCallStatus.complete,
    );
  }

  group('opencodeChildSessionId', () {
    test('reads sessionId from result map', () {
      expect(
        opencodeChildSessionId(
          taskPart(result: {'sessionId': childSessionId}),
        ),
        childSessionId,
      );
    });

    test('reads metadata.sessionId from result map', () {
      expect(
        opencodeChildSessionId(
          taskPart(result: {
            'metadata': {'sessionId': childSessionId},
          }),
        ),
        childSessionId,
      );
    });

    test('parses <task id="ses_…"> from result string', () {
      expect(
        opencodeChildSessionId(
          taskPart(
            result: '<task id="$childSessionId">done</task>',
          ),
        ),
        childSessionId,
      );
    });

    test('returns null when session id is absent', () {
      expect(opencodeChildSessionId(taskPart(result: 'no id here')), isNull);
      expect(opencodeChildSessionId(taskPart()), isNull);
    });
  });

  test('resolves child session messages from task result sessionId', () async {
    await writeParentWithTaskResult(
      taskResult: {'sessionId': childSessionId},
    );
    await writeChildSession(sessionId: childSessionId, parentId: parentSessionId);

    final result = await resolver.resolve(
      part: taskPart(result: {'sessionId': childSessionId}),
      ctx: ctx(dataDir: base.path, persistedNativeId: parentSessionId),
      parentHandle: null,
      rootTranscriptPath: null,
      toolCallAt: DateTime.utc(2026, 7, 28, 4, 30),
    );

    expect(result, isNotNull);
    expect(result!.handle, isA<SubagentSessionHandle>());
    expect(
      (result.handle as SubagentSessionHandle).sessionId,
      childSessionId,
    );
    expect(result.messages, hasLength(1));
    expect(result.messages.first.role, AiRole.user);
    expect(
      (result.messages.first.parts.single as AiTextPart).text,
      'child hello',
    );
  });

  test('resolves nested child using SubagentSessionHandle parent', () async {
    await writeParentWithTaskResult(
      taskResult: {'sessionId': childSessionId},
    );
    await writeChildSession(sessionId: childSessionId, parentId: parentSessionId);
    await writeJson('storage/message/$childSessionId/msg_nested_task.json', {
      'id': 'msg_nested_task',
      'sessionID': childSessionId,
      'role': 'assistant',
      'time': {'created': 5},
    });
    await writeJson('storage/part/msg_nested_task/prt_nested_task.json', {
      'id': 'prt_nested_task',
      'messageID': 'msg_nested_task',
      'type': 'tool',
      'tool': 'task',
      'callID': 'call_nested_task',
      'state': {
        'status': 'completed',
        'output': {'sessionId': nestedChildSessionId},
      },
    });
    await writeChildSession(
      sessionId: nestedChildSessionId,
      parentId: childSessionId,
      userText: 'nested hello',
    );

    final result = await resolver.resolve(
      part: taskPart(result: {'sessionId': nestedChildSessionId}),
      ctx: ctx(dataDir: base.path, persistedNativeId: parentSessionId),
      parentHandle: SubagentSessionHandle(childSessionId),
      rootTranscriptPath: null,
      toolCallAt: DateTime.utc(2026, 7, 28, 4, 31),
    );

    expect(result, isNotNull);
    expect(
      (result!.handle as SubagentSessionHandle).sessionId,
      nestedChildSessionId,
    );
    expect(
      (result.messages.first.parts.single as AiTextPart).text,
      'nested hello',
    );
  });

  test(
    'logs parent_id mismatch via appLogger.w but still resolves',
    () async {
      final logRoot = await Directory.systemTemp.createTemp(
        'opencode_side_resolver_log_',
      );
      addTearDown(() async {
        if (await logRoot.exists()) await logRoot.delete(recursive: true);
      });
      await _ensureFileLogging(logRoot);

      await writeChildSession(
        sessionId: childSessionId,
        parentId: mismatchedParentId,
      );

      final fromPersisted = await resolver.resolve(
        part: taskPart(result: {'sessionId': childSessionId}),
        ctx: ctx(dataDir: base.path, persistedNativeId: parentSessionId),
        parentHandle: null,
        rootTranscriptPath: null,
      );

      expect(fromPersisted, isNotNull);
      expect(
        (fromPersisted!.handle as SubagentSessionHandle).sessionId,
        childSessionId,
      );
      expect(fromPersisted.messages, hasLength(1));
      expect(
        (fromPersisted.messages.first.parts.single as AiTextPart).text,
        'child hello',
      );

      await expectParentIdMismatchLogged(
        childId: childSessionId,
        expectedParent: parentSessionId,
        actualParent: mismatchedParentId,
      );

      await writeChildSession(
        sessionId: nestedChildSessionId,
        parentId: mismatchedParentId,
        userText: 'nested mismatch',
      );

      final fromHandle = await resolver.resolve(
        part: taskPart(result: {'sessionId': nestedChildSessionId}),
        ctx: ctx(dataDir: base.path, persistedNativeId: parentSessionId),
        parentHandle: SubagentSessionHandle(childSessionId),
        rootTranscriptPath: null,
      );

      expect(fromHandle, isNotNull);
      expect(
        (fromHandle!.handle as SubagentSessionHandle).sessionId,
        nestedChildSessionId,
      );
      expect(
        (fromHandle.messages.first.parts.single as AiTextPart).text,
        'nested mismatch',
      );

      await expectParentIdMismatchLogged(
        childId: nestedChildSessionId,
        expectedParent: childSessionId,
        actualParent: mismatchedParentId,
      );
    },
  );

  test('returns null when child session storage is missing', () async {
    await writeParentWithTaskResult(
      taskResult: {'sessionId': childSessionId},
    );

    expect(
      await resolver.resolve(
        part: taskPart(result: {'sessionId': childSessionId}),
        ctx: ctx(dataDir: base.path, persistedNativeId: parentSessionId),
        parentHandle: null,
        rootTranscriptPath: null,
      ),
      isNull,
    );
  });

  test('does not read Claude subagents/ layout', () async {
    final claudeSubagentDir = Directory(p.join(base.path, 'subagents'));
    await claudeSubagentDir.create(recursive: true);
    await File(p.join(claudeSubagentDir.path, 'agent-child.jsonl')).writeAsString(
      '{"type":"user","message":{"role":"user","content":"claude side"}}\n',
    );
    await writeJson('storage/message/$childSessionId/msg_child_user.json', {
      'id': 'msg_child_user',
      'sessionID': childSessionId,
      'role': 'user',
      'time': {'created': 4},
    });
    await writeJson('storage/part/msg_child_user/prt_child_text.json', {
      'id': 'prt_child_text',
      'messageID': 'msg_child_user',
      'type': 'text',
      'text': 'opencode child',
    });

    final result = await resolver.resolve(
      part: taskPart(result: {'sessionId': childSessionId}),
      ctx: ctx(dataDir: base.path, persistedNativeId: parentSessionId),
      parentHandle: null,
      rootTranscriptPath: null,
    );

    expect(result, isNotNull);
    expect(
      (result!.messages.first.parts.single as AiTextPart).text,
      'opencode child',
    );
    expect(
      (result.messages.first.parts.single as AiTextPart).text,
      isNot(contains('claude side')),
    );
  });

  test('returns null when OPENCODE_DB env is missing', () async {
    await writeChildSession(sessionId: childSessionId);

    expect(
      await resolver.resolve(
        part: taskPart(result: {'sessionId': childSessionId}),
        ctx: SessionHistoryContext(
          fs: fs,
          taskId: 'task-1',
          env: const {},
          transcriptRoots: const [],
          bucket: '',
          persistedNativeId: parentSessionId,
        ),
        parentHandle: null,
        rootTranscriptPath: null,
      ),
      isNull,
    );
  });

  group('running child discovery (no tool result yet)', () {
    setUp(() {
      OpencodeSideResolver.clearDiscoveryMemo();
      OpencodeSideResolver.clearChildBundleMemo();
    });

    Future<void> writeRunningParent() async {
      await writeJson('storage/session/proj_demo/$parentSessionId.json', {
        'id': parentSessionId,
        'projectID': 'proj_demo',
        'title': 'parent',
        'time': {'created': 1},
      });
      await writeJson('storage/message/$parentSessionId/msg_task.json', {
        'id': 'msg_task',
        'sessionID': parentSessionId,
        'role': 'assistant',
        'time': {'created': 2},
      });
      await writeJson('storage/part/msg_task/prt_task.json', {
        'id': 'prt_task',
        'messageID': 'msg_task',
        'type': 'tool',
        'tool': 'task',
        'callID': 'call_task_1',
        'state': {
          'status': 'running',
          'input': {'prompt': 'do work'},
          'metadata': {},
        },
      });
    }

    AiToolCallPart runningTaskPart() {
      return AiToolCallPart(
        toolCallId: 'call_task_1',
        toolName: 'task',
        args: const {'prompt': 'do work'},
        status: AiToolCallStatus.incomplete,
      );
    }

    test('discovers child via parent_id linkage when result carries no id',
        () async {
      await writeRunningParent();
      await writeChildSession(
        sessionId: childSessionId,
        parentId: parentSessionId,
        userText: 'child working',
      );

      final result = await resolver.resolve(
        part: runningTaskPart(),
        ctx: ctx(dataDir: base.path, persistedNativeId: parentSessionId),
        parentHandle: null,
        rootTranscriptPath: null,
      );

      expect(result, isNotNull);
      expect(
        (result!.handle as SubagentSessionHandle).sessionId,
        childSessionId,
      );
      expect(
        (result.messages.first.parts.single as AiTextPart).text,
        'child working',
      );
    });

    test('does not discover children of another parent', () async {
      await writeRunningParent();
      await writeChildSession(
        sessionId: childSessionId,
        parentId: 'ses_some_other_parent',
        userText: 'unrelated child',
      );

      expect(
        await resolver.resolve(
          part: runningTaskPart(),
          ctx: ctx(dataDir: base.path, persistedNativeId: parentSessionId),
          parentHandle: null,
          rootTranscriptPath: null,
        ),
        isNull,
      );
    });

    test('prefers the child created after the tool call', () async {
      await writeRunningParent();
      await writeChildSession(
        sessionId: childSessionId,
        parentId: parentSessionId,
        userText: 'older child',
      );
      await writeJson('storage/session/proj_demo/$nestedChildSessionId.json', {
        'id': nestedChildSessionId,
        'projectID': 'proj_demo',
        'title': 'child',
        'time': {'created': 8},
        'parent_id': parentSessionId,
      });
      await writeJson(
        'storage/message/$nestedChildSessionId/msg_child_user.json',
        {
          'id': 'msg_child_user',
          'sessionID': nestedChildSessionId,
          'role': 'user',
          'time': {'created': 9},
        },
      );
      await writeJson(
        'storage/part/msg_child_user/prt_child_text.json',
        {
          'id': 'prt_child_text',
          'messageID': 'msg_child_user',
          'type': 'text',
          'text': 'newer child',
        },
      );

      final result = await resolver.resolve(
        part: runningTaskPart(),
        ctx: ctx(dataDir: base.path, persistedNativeId: parentSessionId),
        parentHandle: null,
        rootTranscriptPath: null,
        toolCallAt: DateTime.fromMillisecondsSinceEpoch(5, isUtc: true),
      );

      expect(result, isNotNull);
      expect(
        (result!.handle as SubagentSessionHandle).sessionId,
        nestedChildSessionId,
      );
      expect(
        (result.messages.first.parts.single as AiTextPart).text,
        'newer child',
      );
    });

    test('resolves nested running child via SubagentSessionHandle parent',
        () async {
      await writeChildSession(
        sessionId: childSessionId,
        parentId: parentSessionId,
        userText: 'child',
      );
      await writeJson('storage/message/$childSessionId/msg_nested_task.json', {
        'id': 'msg_nested_task',
        'sessionID': childSessionId,
        'role': 'assistant',
        'time': {'created': 5},
      });
      await writeJson('storage/part/msg_nested_task/prt_nested_task.json', {
        'id': 'prt_nested_task',
        'messageID': 'msg_nested_task',
        'type': 'tool',
        'tool': 'task',
        'callID': 'call_nested_task',
        'state': {
          'status': 'running',
          'input': {'prompt': 'nested work'},
        },
      });
      await writeChildSession(
        sessionId: nestedChildSessionId,
        parentId: childSessionId,
        userText: 'nested working',
      );

      final result = await resolver.resolve(
        part: AiToolCallPart(
          toolCallId: 'call_nested_task',
          toolName: 'task',
          args: const {'prompt': 'nested work'},
          status: AiToolCallStatus.incomplete,
        ),
        ctx: ctx(dataDir: base.path, persistedNativeId: parentSessionId),
        parentHandle: SubagentSessionHandle(childSessionId),
        rootTranscriptPath: null,
      );

      expect(result, isNotNull);
      expect(
        (result!.handle as SubagentSessionHandle).sessionId,
        nestedChildSessionId,
      );
      expect(
        (result.messages.first.parts.single as AiTextPart).text,
        'nested working',
      );
    });

    test('discoveries from SQLite layout (no JSON storage)', () async {
      final dbPath = p.join(base.path, 'opencode.db');
      final db = sqlite3.open(dbPath);
      addTearDown(db.dispose);
      // Current OpenCode layout: parent_id is a real column.
      db.execute('''
CREATE TABLE session (
  id TEXT PRIMARY KEY,
  parent_id TEXT,
  time_created INTEGER,
  time_updated INTEGER
);
''');
      db.execute(
        '''
INSERT INTO session(id, parent_id, time_created, time_updated)
VALUES ('ses_child003', 'ses_parent001', 3, 3)
''',
      );
      db.execute(
        '''
CREATE TABLE message (
  id TEXT PRIMARY KEY,
  session_id TEXT,
  time_created INTEGER,
  time_updated INTEGER,
  data TEXT
);
CREATE TABLE part (
  id TEXT PRIMARY KEY,
  message_id TEXT,
  session_id TEXT,
  time_created INTEGER,
  time_updated INTEGER,
  data TEXT
);
''',
      );
      db.execute(
        '''
INSERT INTO message(id, session_id, time_created, data)
VALUES (
  'msg_child_user',
  'ses_child003',
  4,
  '{"role":"user","time":{"created":4}}'
)
''',
      );
      db.execute(
        '''
INSERT INTO part(id, message_id, session_id, time_created, data)
VALUES (
  'prt_child_text',
  'msg_child_user',
  'ses_child003',
  4,
  '{"type":"text","text":"db child working"}'
)
''',
      );

      final result = await resolver.resolve(
        part: runningTaskPart(),
        ctx: ctx(dataDir: base.path, persistedNativeId: parentSessionId),
        parentHandle: null,
        rootTranscriptPath: null,
      );

      expect(result, isNotNull);
      expect(
        (result!.handle as SubagentSessionHandle).sessionId,
        'ses_child003',
      );
      expect(
        (result.messages.first.parts.single as AiTextPart).text,
        'db child working',
      );
    });

    test('discovery falls back to legacy data-blob parent linkage', () async {
      final dbPath = p.join(base.path, 'opencode.db');
      final db = sqlite3.open(dbPath);
      addTearDown(db.dispose);
      db.execute('''
CREATE TABLE session (
  id TEXT PRIMARY KEY,
  data TEXT,
  time_created INTEGER
);
''');
      db.execute(
        '''
INSERT INTO session(id, data, time_created)
VALUES (
  'ses_child004',
  '{"id":"ses_child004","parentID":"ses_parent001","time":{"created":3}}',
  3
)
''',
      );
      db.execute(
        '''
CREATE TABLE message (
  id TEXT PRIMARY KEY,
  session_id TEXT,
  time_created INTEGER,
  data TEXT
);
CREATE TABLE part (
  id TEXT PRIMARY KEY,
  message_id TEXT,
  session_id TEXT,
  time_created INTEGER,
  data TEXT
);
''',
      );
      db.execute(
        '''
INSERT INTO message(id, session_id, time_created, data)
VALUES (
  'msg_child_user',
  'ses_child004',
  4,
  '{"role":"user","time":{"created":4}}'
)
''',
      );
      db.execute(
        '''
INSERT INTO part(id, message_id, session_id, time_created, data)
VALUES (
  'prt_child_text',
  'msg_child_user',
  'ses_child004',
  4,
  '{"type":"text","text":"legacy child"}'
)
''',
      );

      final result = await resolver.resolve(
        part: runningTaskPart(),
        ctx: ctx(dataDir: base.path, persistedNativeId: parentSessionId),
        parentHandle: null,
        rootTranscriptPath: null,
      );

      expect(result, isNotNull);
      expect(
        (result!.handle as SubagentSessionHandle).sessionId,
        'ses_child004',
      );
      expect(
        (result.messages.first.parts.single as AiTextPart).text,
        'legacy child',
      );
    });

    test('does not discover for completed/error parts without a result id',
        () async {
      await writeRunningParent();
      await writeChildSession(
        sessionId: childSessionId,
        parentId: parentSessionId,
        userText: 'child',
      );

      // A completed part whose result carries no session id must degrade
      // (null) instead of scanning the store for a "running" child.
      expect(
        await resolver.resolve(
          part: AiToolCallPart(
            toolCallId: 'call_task_1',
            toolName: 'task',
            args: const {'prompt': 'do work'},
            status: AiToolCallStatus.complete,
          ),
          ctx: ctx(dataDir: base.path, persistedNativeId: parentSessionId),
          parentHandle: null,
          rootTranscriptPath: null,
        ),
        isNull,
      );
    });

    test('returns null when no running child exists', () async {
      await writeRunningParent();

      expect(
        await resolver.resolve(
          part: runningTaskPart(),
          ctx: ctx(dataDir: base.path, persistedNativeId: parentSessionId),
          parentHandle: null,
          rootTranscriptPath: null,
        ),
        isNull,
      );
    });

    test('discovery memo invalidates when the store moves', () async {
      await writeRunningParent();
      await writeChildSession(
        sessionId: childSessionId,
        parentId: parentSessionId,
        userText: 'first child',
      );

      final first = await resolver.resolve(
        part: runningTaskPart(),
        ctx: ctx(dataDir: base.path, persistedNativeId: parentSessionId),
        parentHandle: null,
        rootTranscriptPath: null,
      );
      expect(
        (first!.handle as SubagentSessionHandle).sessionId,
        childSessionId,
      );

      // A newer child of the same parent appears → the fingerprint moves and
      // the memo must not serve the stale child.
      await writeJson('storage/session/proj_demo/$nestedChildSessionId.json', {
        'id': nestedChildSessionId,
        'projectID': 'proj_demo',
        'title': 'child',
        'time': {'created': 8},
        'parent_id': parentSessionId,
      });
      await writeJson(
        'storage/message/$nestedChildSessionId/msg_child_user.json',
        {
          'id': 'msg_child_user',
          'sessionID': nestedChildSessionId,
          'role': 'user',
          'time': {'created': 9},
        },
      );
      await writeJson(
        'storage/part/msg_child_user/prt_child_text.json',
        {
          'id': 'prt_child_text',
          'messageID': 'msg_child_user',
          'type': 'text',
          'text': 'second child',
        },
      );
      final second = await resolver.resolve(
        part: runningTaskPart(),
        ctx: ctx(dataDir: base.path, persistedNativeId: parentSessionId),
        parentHandle: null,
        rootTranscriptPath: null,
      );
      expect(
        (second!.handle as SubagentSessionHandle).sessionId,
        nestedChildSessionId,
      );

      // Unchanged store → memo hit still returns the same (fresh) child.
      final third = await resolver.resolve(
        part: runningTaskPart(),
        ctx: ctx(dataDir: base.path, persistedNativeId: parentSessionId),
        parentHandle: null,
        rootTranscriptPath: null,
      );
      expect(
        (third!.handle as SubagentSessionHandle).sessionId,
        nestedChildSessionId,
      );
    });

    test('discovery memo does not serve children that vanished', () async {
      await writeRunningParent();
      await writeChildSession(
        sessionId: childSessionId,
        parentId: parentSessionId,
        userText: 'child',
      );

      final first = await resolver.resolve(
        part: runningTaskPart(),
        ctx: ctx(dataDir: base.path, persistedNativeId: parentSessionId),
        parentHandle: null,
        rootTranscriptPath: null,
      );
      expect(first, isNotNull);

      // Remove the child's session file → the store fingerprint moves and the
      // re-scan finds nothing; the memo must not resurrect the old child.
      final sessionFile = File(
        p.join(base.path, 'storage', 'session', 'proj_demo', '$childSessionId.json'),
      );
      await sessionFile.delete();

      expect(
        await resolver.resolve(
          part: runningTaskPart(),
          ctx: ctx(dataDir: base.path, persistedNativeId: parentSessionId),
          parentHandle: null,
          rootTranscriptPath: null,
        ),
        isNull,
      );
    });
  });
}
