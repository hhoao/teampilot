import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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
}
