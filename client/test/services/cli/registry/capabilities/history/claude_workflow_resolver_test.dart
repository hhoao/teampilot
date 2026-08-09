import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/workflow_resolver.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/subagent_side_resolver.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/session/subagent_side_transcript_path.dart';

import '../../../../../support/in_memory_filesystem.dart';

const _parentPath = '/projects/enc/ses-1.jsonl';
const _runId = 'wf_871552ba-110';
const _taskId = 'wh8pw12dw';
const _toolCallId = 'call_00_1mjZUYbD5Btsf7KubuTm7229';

SessionHistoryContext _ctx(Filesystem fs) => SessionHistoryContext(
  fs: fs,
  taskId: 'task-1',
  env: const {},
  transcriptRoots: const [],
  bucket: 'bucket',
);

Future<SubagentSideResolveResult?> _resolve({
  required Filesystem fs,
  required AiToolCallPart part,
}) {
  return const ClaudeWorkflowResolver().resolve(
    part: part,
    ctx: _ctx(fs),
    parentTranscriptPath: _parentPath,
  );
}

/// Parent transcript that pairs [toolCallId] with [taskId] through a
/// `<task-notification>` (as Claude Code writes in `queue-operation` and
/// injected `user` records).
String _parentJsonl(String toolCallId, String taskId) {
  final notification =
      '<task-notification>\n<task-id>$taskId</task-id>\n'
      '<tool-use-id>$toolCallId</tool-use-id>\n</task-notification>';
  return [
    jsonEncode({
      'type': 'user',
      'message': {'role': 'user', 'content': 'start'},
      'uuid': 'u0',
      'timestamp': '2026-08-07T09:00:00.000Z',
    }),
    jsonEncode({
      'type': 'queue-operation',
      'operation': 'enqueue',
      'content': notification,
      'timestamp': '2026-08-07T09:00:01.000Z',
    }),
  ].join('\n');
}

String _runRecordJson({String? status, int agentCount = 2}) {
  return jsonEncode({
    'runId': _runId,
    'taskId': _taskId,
    'workflowName': 'migrate-inkwell-task',
    'status': status ?? 'DONE',
    'phases': ['Implement', 'Spec review', 'Quality review'],
    'agentCount': agentCount,
    'summary': 'migrated all four sites',
    'durationMs': 160000,
    'result': {'summary': 'result summary'},
  });
}

String _agentJsonl(String rolePrompt, String done) {
  return [
    jsonEncode({
      'type': 'user',
      'message': {'role': 'user', 'content': rolePrompt},
      'uuid': 'u-${rolePrompt.hashCode}',
      'timestamp': '2026-08-07T09:01:00.000Z',
    }),
    jsonEncode({
      'type': 'assistant',
      'message': {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': done},
        ],
      },
      'uuid': 'a-${done.hashCode}',
      'timestamp': '2026-08-07T09:01:30.000Z',
    }),
  ].join('\n');
}

String _journalJsonl(List<({String agentId, String status})> entries) {
  return [
    for (final e in entries)
      jsonEncode({
        'type': 'result',
        'key': 'v2:${e.agentId}',
        'agentId': e.agentId,
        'result': {
          'status': e.status,
          'summary': 'agent ${e.agentId} summary',
        },
      }),
  ].join('\n');
}

Future<void> _writeRunFixtures(
  Filesystem fs, {
  int agentCount = 2,
  String? runStatus,
}) async {
  final workflowsDir = claudeWorkflowsDirFor(_parentPath);
  final runDir = claudeWorkflowRunDirFor(_parentPath, runId: _runId);
  await fs.writeString(
    '$workflowsDir/$_runId.json',
    _runRecordJson(status: runStatus, agentCount: agentCount),
  );
  for (var i = 0; i < agentCount; i++) {
    final agentId = 'agent-${i}a';
    await fs.writeString(
      '$runDir/agent-$agentId.jsonl',
      _agentJsonl('You are the Implementer for task $i', 'done $i'),
    );
  }
  await fs.writeString(
    '$runDir/journal.jsonl',
    _journalJsonl([
      for (var i = 0; i < agentCount; i++)
        (agentId: 'agent-${i}a', status: 'DONE'),
    ]),
  );
}

void main() {
  setUp(ClaudeWorkflowResolver.clearWorkflowCache);

  const part = AiToolCallPart(
    toolCallId: _toolCallId,
    toolName: 'Workflow',
    args: {'script': 'export const meta = {};'},
  );

  test('inline script Workflow resolves run + per-agent transcripts', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString(_parentPath, _parentJsonl(_toolCallId, _taskId));
    await _writeRunFixtures(fs);

    final result = await _resolve(fs: fs, part: part);

    expect(result, isNotNull);
    final workflow = result!.workflow;
    expect(workflow, isNotNull);
    expect(workflow!.runId, _runId);
    expect(workflow.workflowName, 'migrate-inkwell-task');
    expect(workflow.status, 'DONE');
    expect(workflow.phases, ['Implement', 'Spec review', 'Quality review']);
    expect(workflow.agentCount, 2);
    expect(workflow.summary, 'migrated all four sites');
    expect(workflow.duration, const Duration(seconds: 160));
    expect(workflow.agents, hasLength(2));

    final first = workflow.agents.first;
    expect(first.role, contains('Implementer'));
    expect(first.status, 'DONE');
    expect(first.messages, isNotEmpty);
    expect(first.handle.path, endsWith('agent-agent-0a.jsonl'));
  });

  test('scriptPath Workflow call resolves through task-notification', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString(_parentPath, _parentJsonl(_toolCallId, _taskId));
    await _writeRunFixtures(fs);

    final result = await _resolve(
      fs: fs,
      part: const AiToolCallPart(
        toolCallId: _toolCallId,
        toolName: 'Workflow',
        args: {'scriptPath': '…/workflows/scripts/migrate-$_runId.json'},
      ),
    );

    expect(result, isNotNull);
    expect(result!.workflow!.runId, _runId);
    expect(result.workflow!.agents, hasLength(2));
  });

  test('no task-notification for the tool call -> null (cancelled run)',
      () async {
    final fs = InMemoryFilesystem();
    await fs.writeString(
      _parentPath,
      _parentJsonl('call_other', 'other-task'),
    );
    await _writeRunFixtures(fs);

    final result = await _resolve(fs: fs, part: part);
    expect(result, isNull);
  });

  test('run record missing for taskId -> null', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString(_parentPath, _parentJsonl(_toolCallId, 'unknown-task'));
    await _writeRunFixtures(fs);

    final result = await _resolve(fs: fs, part: part);
    expect(result, isNull);
  });

  test('run with no agent transcripts -> workflow with empty agents',
      () async {
    final fs = InMemoryFilesystem();
    await fs.writeString(_parentPath, _parentJsonl(_toolCallId, _taskId));
    await _writeRunFixtures(fs, agentCount: 0);

    final result = await _resolve(fs: fs, part: part);
    expect(result, isNotNull);
    expect(result!.workflow!.agents, isEmpty);
    expect(result.workflow!.agentCount, 0);
  });

  test('isWorkflowTool matches casing variants', () {
    expect(isWorkflowTool('Workflow'), isTrue);
    expect(isWorkflowTool('workflow'), isTrue);
    expect(isWorkflowTool('Work_Flow'), isTrue);
    expect(isWorkflowTool('Agent'), isFalse);
    expect(isWorkflowTool(null), isFalse);
    expect(isWorkflowTool(''), isFalse);
  });

  test('unchanged run reuses parsed agents across resolves (no re-read)',
      () async {
    final workflowsDir = claudeWorkflowsDirFor(_parentPath);
    final runDir = claudeWorkflowRunDirFor(_parentPath, runId: _runId);
    final fs = _CountingReadFilesystem();
    await fs.writeString(_parentPath, _parentJsonl(_toolCallId, _taskId));
    await _writeRunFixtures(fs);
    fs.setMtime(_parentPath, DateTime.utc(2026, 8, 7, 10));
    fs.setMtime(
      '$workflowsDir/$_runId.json',
      DateTime.utc(2026, 8, 7, 10, 1),
    );
    fs.setMtime('$runDir/agent-agent-0a.jsonl', DateTime.utc(2026, 8, 7, 10, 2));
    fs.setMtime('$runDir/agent-agent-1a.jsonl', DateTime.utc(2026, 8, 7, 10, 3));
    fs.setMtime('$runDir/journal.jsonl', DateTime.utc(2026, 8, 7, 10, 4));

    final first = await _resolve(fs: fs, part: part);
    expect(first!.workflow!.agents, hasLength(2));

    fs.agentReads.clear();
    final second = await _resolve(fs: fs, part: part);
    expect(second!.workflow!.agents, hasLength(2));
    expect(second.workflow!.agents.first.role, contains('Implementer'));
    expect(fs.agentReads, isEmpty,
        reason: 'unchanged agent files must be reused, not re-read');
  });

  test('appended agent transcript is re-parsed; unchanged ones reused',
      () async {
    final workflowsDir = claudeWorkflowsDirFor(_parentPath);
    final runDir = claudeWorkflowRunDirFor(_parentPath, runId: _runId);
    final fs = _CountingReadFilesystem();
    await fs.writeString(_parentPath, _parentJsonl(_toolCallId, _taskId));
    await _writeRunFixtures(fs);
    fs.setMtime(_parentPath, DateTime.utc(2026, 8, 7, 10));
    fs.setMtime(
      '$workflowsDir/$_runId.json',
      DateTime.utc(2026, 8, 7, 10, 1),
    );
    fs.setMtime('$runDir/agent-agent-0a.jsonl', DateTime.utc(2026, 8, 7, 10, 2));
    fs.setMtime('$runDir/agent-agent-1a.jsonl', DateTime.utc(2026, 8, 7, 10, 3));
    fs.setMtime('$runDir/journal.jsonl', DateTime.utc(2026, 8, 7, 10, 4));

    final first = await _resolve(fs: fs, part: part);
    expect(first!.workflow!.agents, hasLength(2));

    fs.agentReads.clear();
    await fs.writeString(
      '$runDir/agent-agent-0a.jsonl',
      _agentJsonl('You are the Implementer for task 0 (updated)', 'done 0 v2'),
    );
    fs.setMtime('$runDir/agent-agent-0a.jsonl', DateTime.utc(2026, 8, 7, 10, 5));

    final second = await _resolve(fs: fs, part: part);
    expect(second!.workflow!.agents, hasLength(2));
    expect(fs.agentReads, contains('$runDir/agent-agent-0a.jsonl'),
        reason: 'the grown agent must be re-read');
    expect(fs.agentReads, isNot(contains('$runDir/agent-agent-1a.jsonl')),
        reason: 'the unchanged agent must be reused');
    expect(second.workflow!.agents.first.role, contains('updated'));
  });
}

class _MtimeFilesystem extends InMemoryFilesystem {
  final Map<String, DateTime> mtimes = {};

  void setMtime(String path, DateTime mtime) => mtimes[path] = mtime;

  @override
  Future<FsStat> stat(String path) async {
    final base = await super.stat(path);
    if (!base.exists) return base;
    return FsStat(
      kind: base.kind,
      size: base.size,
      mtime: mtimes[path],
    );
  }
}

class _CountingReadFilesystem extends _MtimeFilesystem {
  final Set<String> agentReads = {};

  @override
  Future<String?> readString(String path) async {
    if (path.contains('/subagents/workflows/') &&
        path.endsWith('.jsonl') &&
        !path.endsWith('journal.jsonl')) {
      agentReads.add(path);
    }
    return super.readString(path);
  }
}
