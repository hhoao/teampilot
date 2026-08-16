import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:teampilot/services/cli/opencode/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/opencode/capabilities/history/side_resolver.dart';
import 'package:teampilot/services/cli/opencode/capabilities/sqlite_worker_pool.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/session_history_context.dart';

void main() {
  late Directory base;
  final fs = LocalFilesystem();
  const resolver = OpencodeSideResolver();

  const parentSessionId = 'ses_parent001';
  const childSessionId = 'ses_child001';
  const nestedChildSessionId = 'ses_child002';

  setUp(() async {
    base = await Directory.systemTemp.createTemp('opencode_side_resolver_');
    // Child-bundle / discovery memos are static and keyed by child id +
    // fingerprint; sibling tests reuse the same ids with identical
    // fingerprints, so the memos must not leak across tests.
    OpencodeSideResolver.clearChildBundleMemo();
    OpencodeSideResolver.clearDiscoveryMemo();
    OpencodeSideResolver.clearChildResultMemo();
  });

  tearDown(() async {
    await OpencodeSqliteWorkerPool.instance.disposeAllAndWait();
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

  /// Current OpenCode SQLite layout: parent_id is a real column.
  Database openDb() {
    final db = sqlite3.open(p.join(base.path, 'opencode.db'));
    addTearDown(db.dispose);
    db.execute('''
CREATE TABLE session (
  id TEXT PRIMARY KEY,
  parent_id TEXT,
  time_created INTEGER,
  time_updated INTEGER,
  data TEXT
);
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
''');
    return db;
  }

  /// One user message (+ text part) for a child session, plus its session row.
  /// Message/part ids derive from [sessionId] so they stay unique per DB.
  void insertChildSession(
    Database db, {
    required String sessionId,
    String? parentId,
    String userText = 'child hello',
    int created = 3,
  }) {
    db.execute(
      'INSERT INTO session(id, parent_id, time_created, time_updated, data) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        sessionId,
        parentId,
        created,
        created,
        jsonEncode({'id': sessionId, 'time': {'created': created}}),
      ],
    );
    final msgId = 'msg_u_$sessionId';
    db.execute(
      'INSERT INTO message(id, session_id, time_created, data) '
      'VALUES (?, ?, ?, ?)',
      [
        msgId,
        sessionId,
        created + 1,
        jsonEncode({
          'id': msgId,
          'sessionID': sessionId,
          'role': 'user',
          'time': {'created': created + 1},
        }),
      ],
    );
    db.execute(
      'INSERT INTO part(id, message_id, session_id, time_created, data) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        'prt_u_$sessionId',
        msgId,
        sessionId,
        created + 1,
        jsonEncode({
          'id': 'prt_u_$sessionId',
          'messageID': msgId,
          'type': 'text',
          'text': userText,
        }),
      ],
    );
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

  AiToolCallPart runningTaskPart() {
    return AiToolCallPart(
      toolCallId: 'call_task_1',
      toolName: 'task',
      args: const {'prompt': 'do work'},
      status: AiToolCallStatus.incomplete,
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

    test('extracts child session id from an adapter-parsed task part (G7)',
        () async {
      // 端到端：adapter 内联 state.output（含 <task id="ses_…"> 包裹）→
      // opencodeChildSessionId 提取出非空子会话 id（agentId 非空语义）。
      final messages = await const OpencodeAiTranscriptAdapter().parse(
        AiTranscriptBundle(
          adapterId: 'opencode',
          fragments: [
            AiTranscriptFragment(
              name: 'message/msg_task.json',
              bytes: utf8.encode(
                jsonEncode({
                  'id': 'msg_task',
                  'role': 'assistant',
                  'time': {'created': 1},
                }),
              ),
            ),
            AiTranscriptFragment(
              name: 'part/msg_task/prt_task.json',
              bytes: utf8.encode(
                jsonEncode({
                  'id': 'prt_task',
                  'type': 'tool',
                  'tool': 'task',
                  'callID': 'call_task_1',
                  'state': {
                    'status': 'completed',
                    'input': {'prompt': 'do work'},
                    'output': '<task id="$childSessionId" state="completed">'
                        '<task_result>done</task_result></task>',
                  },
                }),
              ),
            ),
          ],
        ),
      );

      final part = messages
          .expand((m) => m.parts)
          .whereType<AiToolCallPart>()
          .single;
      expect(part.toolName, 'task');
      expect(part.result, isNotNull);
      expect(opencodeChildSessionId(part), childSessionId);
    });

    test('trims whitespace-only session ids to null (G7 agentId 非空)',
        () async {
      expect(opencodeChildSessionId(taskPart(result: {'sessionId': '  '})),
          isNull);
      expect(opencodeChildSessionId(taskPart(result: {'sessionId': '\t'})),
          isNull);
      expect(
        opencodeChildSessionId(
          taskPart(result: {'metadata': {'sessionId': ' '}}),
        ),
        isNull,
      );
    });
  });

  test('resolves child session messages from task result sessionId', () async {
    final db = openDb();
    insertChildSession(db, sessionId: childSessionId, parentId: parentSessionId);

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

  test(
    'unchanged child re-resolve returns the identical message list (memo)',
    () async {
      final db = openDb();
      insertChildSession(
        db,
        sessionId: childSessionId,
        parentId: parentSessionId,
      );
      final runCtx = ctx(dataDir: base.path, persistedNativeId: parentSessionId);

      final first = await resolver.resolve(
        part: taskPart(result: {'sessionId': childSessionId}),
        ctx: runCtx,
        parentHandle: null,
        rootTranscriptPath: null,
      );
      expect(first, isNotNull);
      final second = await resolver.resolve(
        part: taskPart(result: {'sessionId': childSessionId}),
        ctx: runCtx,
        parentHandle: null,
        rootTranscriptPath: null,
      );

      expect(
        identical(first!.messages, second!.messages),
        isTrue,
        reason: '子会话未变化时重复 resolve 必须复用同一消息列表实例——'
            'seat 的 identical 快速路径依赖它,否则每次刷新都要做内容比较'
            '(性能回归)',
      );
    },
  );

  test('child growth re-parses only after the fingerprint moves', () async {
    final db = openDb();
    insertChildSession(
      db,
      sessionId: childSessionId,
      parentId: parentSessionId,
    );
    final runCtx = ctx(dataDir: base.path, persistedNativeId: parentSessionId);

    final first = await resolver.resolve(
      part: taskPart(result: {'sessionId': childSessionId}),
      ctx: runCtx,
      parentHandle: null,
      rootTranscriptPath: null,
    );
    expect(first!.messages, hasLength(1));

    // 子会话追加一条 message + part → 指纹移动 → 必须重新解析出增长后的
    // 内容(否则运行中的预览永远停留在旧快照)。
    final msgId = 'msg_grow_$childSessionId';
    db.execute(
      'INSERT INTO message(id, session_id, time_created, time_updated, data) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        msgId,
        childSessionId,
        50,
        50,
        jsonEncode({
          'id': msgId,
          'sessionID': childSessionId,
          'role': 'assistant',
          'time': {'created': 50},
        }),
      ],
    );
    db.execute(
      'INSERT INTO part(id, message_id, session_id, time_created, '
      'time_updated, data) VALUES (?, ?, ?, ?, ?, ?)',
      [
        'prt_grow_$childSessionId',
        msgId,
        childSessionId,
        50,
        50,
        jsonEncode({
          'id': 'prt_grow_$childSessionId',
          'messageID': msgId,
          'type': 'text',
          'text': 'more progress',
        }),
      ],
    );

    final second = await resolver.resolve(
      part: taskPart(result: {'sessionId': childSessionId}),
      ctx: runCtx,
      parentHandle: null,
      rootTranscriptPath: null,
    );
    expect(second, isNotNull);
    expect(second!.messages, hasLength(2));
    expect(
      (second.messages.last.parts.single as AiTextPart).text,
      'more progress',
    );
  });

  test('resolves nested child using SubagentSessionHandle parent', () async {
    final db = openDb();
    insertChildSession(db, sessionId: childSessionId, parentId: parentSessionId);
    insertChildSession(
      db,
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

  test('returns null when child session storage is missing', () async {
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
    final db = openDb();
    insertChildSession(
      db,
      sessionId: childSessionId,
      parentId: parentSessionId,
      userText: 'opencode child',
    );

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
    final db = openDb();
    insertChildSession(db, sessionId: childSessionId);

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
    test('discovers child via parent_id linkage when result carries no id',
        () async {
      final db = openDb();
      insertChildSession(
        db,
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
      final db = openDb();
      insertChildSession(
        db,
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
      final db = openDb();
      insertChildSession(
        db,
        sessionId: childSessionId,
        parentId: parentSessionId,
        userText: 'older child',
      );
      insertChildSession(
        db,
        sessionId: nestedChildSessionId,
        parentId: parentSessionId,
        userText: 'newer child',
        created: 8,
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
      final db = openDb();
      insertChildSession(
        db,
        sessionId: childSessionId,
        parentId: parentSessionId,
        userText: 'child',
      );
      insertChildSession(
        db,
        sessionId: nestedChildSessionId,
        parentId: childSessionId,
        userText: 'nested working',
      );

      final result = await resolver.resolve(
        part: runningTaskPart(),
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

    test('discovery falls back to legacy data-blob parent linkage', () async {
      final db = sqlite3.open(p.join(base.path, 'opencode.db'));
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
      final db = openDb();
      insertChildSession(
        db,
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
      openDb();

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
      final db = openDb();
      insertChildSession(
        db,
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

      // A newer child of the same parent appears → the store moves and the
      // memo must not serve the stale child.
      insertChildSession(
        db,
        sessionId: nestedChildSessionId,
        parentId: parentSessionId,
        userText: 'second child',
        created: 8,
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
      final db = openDb();
      insertChildSession(
        db,
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

      // Remove the child's session row → the store fingerprint moves and the
      // re-scan finds nothing; the memo must not resurrect the old child.
      db.execute('DELETE FROM session WHERE id = ?', [childSessionId]);

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
