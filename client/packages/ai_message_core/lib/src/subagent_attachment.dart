import 'message.dart';

enum AiSubagentAttachmentSource { sideTranscript, toolResult }

sealed class SubagentSideHandle {
  const SubagentSideHandle();
}

final class SubagentFileHandle extends SubagentSideHandle {
  const SubagentFileHandle(this.path);
  final String path;
}

final class SubagentSessionHandle extends SubagentSideHandle {
  const SubagentSessionHandle(this.sessionId);
  final String sessionId;
}

/// One agent spawned by a Claude `Workflow` run: parsed transcript plus its
/// role / status. The inflater fans these out into per-agent attachments keyed
/// [subagentWorkflowChildToolCallId].
class SubagentWorkflowAgent {
  const SubagentWorkflowAgent({
    required this.agentId,
    required this.messages,
    required this.handle,
    this.role,
    this.status,
  });

  final String agentId;
  final String? role;
  final String? status;
  final List<AiMessage> messages;
  final SubagentFileHandle handle;

  SubagentWorkflowAgent copyWith({
    String? agentId,
    String? role,
    String? status,
    List<AiMessage>? messages,
    SubagentFileHandle? handle,
  }) {
    return SubagentWorkflowAgent(
      agentId: agentId ?? this.agentId,
      role: role ?? this.role,
      status: status ?? this.status,
      messages: messages ?? this.messages,
      handle: handle ?? this.handle,
    );
  }
}

/// Run-level metadata for a Claude `Workflow` tool call, resolved from the run
/// record (`…/workflows/wf_{runId}.json`) plus its per-agent transcripts.
class SubagentWorkflowInfo {
  const SubagentWorkflowInfo({
    required this.runId,
    this.workflowName,
    this.status,
    this.phases = const [],
    this.agentCount = 0,
    this.summary,
    this.duration,
    this.agents = const [],
  });

  final String runId;
  final String? workflowName;
  final String? status;
  final List<String> phases;
  final int agentCount;
  final String? summary;
  final Duration? duration;
  final List<SubagentWorkflowAgent> agents;

  SubagentWorkflowInfo copyWith({
    String? runId,
    String? workflowName,
    String? status,
    List<String>? phases,
    int? agentCount,
    String? summary,
    Duration? duration,
    List<SubagentWorkflowAgent>? agents,
  }) {
    return SubagentWorkflowInfo(
      runId: runId ?? this.runId,
      workflowName: workflowName ?? this.workflowName,
      status: status ?? this.status,
      phases: phases ?? this.phases,
      agentCount: agentCount ?? this.agentCount,
      summary: summary ?? this.summary,
      duration: duration ?? this.duration,
      agents: agents ?? this.agents,
    );
  }
}

/// Synthetic attachment key for one workflow agent: `'{runId}/{agentId}'`.
String subagentWorkflowChildToolCallId(String runId, String agentId) =>
    '$runId/$agentId';

class AiSubagentAttachment {
  const AiSubagentAttachment({
    required this.toolCallId,
    required this.messages,
    required this.source,
    this.title,
    this.handle,
    this.workflow,
  });

  final String toolCallId;
  final List<AiMessage> messages;
  final AiSubagentAttachmentSource source;
  final String? title;
  final SubagentSideHandle? handle;

  /// Present when this attachment is the aggregate of a Claude `Workflow` run.
  final SubagentWorkflowInfo? workflow;

  AiSubagentAttachment copyWith({
    String? toolCallId,
    List<AiMessage>? messages,
    AiSubagentAttachmentSource? source,
    String? title,
    SubagentSideHandle? handle,
    SubagentWorkflowInfo? workflow,
  }) {
    return AiSubagentAttachment(
      toolCallId: toolCallId ?? this.toolCallId,
      messages: messages ?? this.messages,
      source: source ?? this.source,
      title: title ?? this.title,
      handle: handle ?? this.handle,
      workflow: workflow ?? this.workflow,
    );
  }

  /// File-handle path for debug/compat; null for session handles.
  String? get sidePath {
    final h = handle;
    if (h is SubagentFileHandle) return h.path;
    return null;
  }
}
String? subagentTitleFromPart(AiToolCallPart part) {
  final args = part.args;
  if (args != null) {
    final description = _trimmedString(args['description']);
    if (description != null) return description;
    final taskName = _trimmedString(args['task_name']);
    if (taskName != null) return taskName;
    final prompt = _trimmedString(args['prompt']);
    if (prompt != null) return prompt;
  }
  return null;
}

String? subagentAgentIdFromPart(AiToolCallPart part) {
  final fromArgs = _agentIdFromMap(part.args);
  if (fromArgs != null) return fromArgs;

  final result = part.result;
  if (result is Map) {
    return _agentIdFromMap(Map<String, Object?>.from(result));
  }
  return null;
}

List<AiMessage> syntheticSubagentMessagesFromResult({
  required String toolCallId,
  required Object? result,
}) {
  if (result == null) return const [];

  final text = switch (result) {
    String s => s.trim(),
    _ => result.toString().trim(),
  };
  if (text.isEmpty) return const [];

  return [
    AiMessage(
      id: 'subagent-result-$toolCallId',
      role: AiRole.assistant,
      parts: [AiTextPart(text: text)],
    ),
  ];
}

String? _trimmedString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _agentIdFromMap(Map<String, Object?>? map) {
  if (map == null) return null;
  for (final key in const ['agentId', 'agent_id']) {
    final value = map[key];
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
  }
  return null;
}
