import 'message.dart';
import 'subagent_attachment.dart';

/// Parsed workflow tool call ready for chat chrome.
class AiWorkflowTarget {
  const AiWorkflowTarget({this.workflow});

  /// Null when the host has no run record for this tool call.
  final SubagentWorkflowInfo? workflow;
}

abstract class AiWorkflowResolver {
  AiWorkflowTarget? resolve(AiToolCallPart part);
}
