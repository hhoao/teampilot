import 'agent_attention_state.dart';
import 'agent_status_event.dart';

/// True for ExitPlanMode across casing variants (`ExitPlanMode`,
/// `exit_plan_mode`, `exitPlanMode`). ExitPlanMode presents a plan for
/// approval, so the seat must stay in waiting attention until the user
/// confirms in the Terminal.
bool isExitPlanModeTool(String? toolName) {
  if (toolName == null || toolName.isEmpty) return false;
  final compact = toolName
      .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
      .toLowerCase();
  return compact == 'exitplanmode';
}

/// Keeps the structured ExitPlanMode payload when a later waiting hook (often
/// `PermissionRequest`) arrives without `tool_input.plan`.
AgentStatusEvent preserveExitPlanModePayload(
  AgentStatusEvent? previous,
  AgentStatusEvent next,
) {
  if (previous == null) return next;
  if (next.planText != null || next.planFilePath != null) return next;
  if (next.state != AgentSeatAttention.waiting) return next;
  if (!isExitPlanModeTool(previous.toolName)) return next;

  final nextTool = next.toolName?.trim() ?? '';
  if (nextTool.isNotEmpty && !isExitPlanModeTool(nextTool)) return next;

  return next.copyWith(
    planText: previous.planText,
    planFilePath: previous.planFilePath,
  );
}

/// Reads the Claude `ExitPlanMode` plan body from `tool_input`.
///
/// Lenient by design: the CLI schema has drifted between versions (`plan`,
/// `planText`, `plan_text`) and the plan may be injected from disk before the
/// hook fires.
String? parseExitPlanModeText(Object? toolInput) {
  if (toolInput is! Map) return null;
  final raw =
      toolInput['plan'] ?? toolInput['planText'] ?? toolInput['plan_text'];
  if (raw is! String) return null;
  final text = raw.trim();
  return text.isEmpty ? null : text;
}

/// Reads the Claude `ExitPlanMode` plan file path from `tool_input`.
String? parseExitPlanModeFilePath(Object? toolInput) {
  if (toolInput is! Map) return null;
  final raw =
      toolInput['planFilePath'] ??
      toolInput['plan_file_path'] ??
      toolInput['file_path'] ??
      toolInput['filePath'];
  if (raw is! String) return null;
  final path = raw.trim();
  return path.isEmpty ? null : path;
}
