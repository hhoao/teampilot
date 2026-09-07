/// Claude-family background shell task hook parsing.
///
/// Start signal: `PreToolUse` (Bash) with `tool_input.run_in_background ==
/// true` and a non-empty `tool_use_id` (the lease pairing key). The tool
/// call returns immediately, so the turn's `Stop` may fire long before the
/// task finishes — the latch must survive it.
///
/// Completion signal: the CLI's re-invocation fires `UserPromptSubmit`
/// whose prompt is a `<task-notification>` block carrying the matching
/// `<tool-use-id>`. Real user prompts never release.
///
/// Payload shapes verified against claude 2.1.156 — see
/// docs/specs/2026-09-07-background-task-terminal-protection-design.md.

/// True when [body] is the start of a background shell task.
bool isBackgroundTaskStart(Map<String, Object?> body) {
  if (body['hook_event_name'] != 'PreToolUse') return false;
  if (body['tool_name'] != 'Bash') return false;
  final toolInput = body['tool_input'];
  if (toolInput is! Map) return false;
  if (toolInput['run_in_background'] != true) return false;
  return (body['tool_use_id']?.toString() ?? '').trim().isNotEmpty;
}

/// The `<tool-use-id>` inside a `<task-notification>` [prompt], or null when
/// the prompt is anything else (real user input).
String? taskNotificationToolUseId(String? prompt) {
  if (prompt == null) return null;
  final trimmed = prompt.trim();
  if (!trimmed.startsWith('<task-notification>')) return null;
  final match = RegExp(
    r'<tool-use-id>\s*([^<]+?)\s*</tool-use-id>',
  ).firstMatch(trimmed);
  return match?.group(1);
}
