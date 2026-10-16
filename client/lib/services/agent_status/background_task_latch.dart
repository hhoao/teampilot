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
library;

/// True when [body] is the start of a background shell task.
bool isBackgroundTaskStart(Map<String, Object?> body) {
  if (body['hook_event_name'] != 'PreToolUse') return false;
  if (body['tool_name'] != 'Bash') return false;
  final toolInput = body['tool_input'];
  if (toolInput is! Map) return false;
  if (toolInput['run_in_background'] != true) return false;
  return (body['tool_use_id']?.toString() ?? '').trim().isNotEmpty;
}

/// One entry of Claude's authoritative `background_tasks[]` snapshot.
///
/// `type` is a friendly label — `shell`, `subagent`, `monitor`, `workflow`
/// (falls back to the raw discriminant for unknown types).
class BackgroundTaskRef {
  const BackgroundTaskRef({required this.id, required this.type});

  final String id;
  final String type;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackgroundTaskRef && id == other.id && type == other.type;

  @override
  int get hashCode => Object.hash(id, type);

  @override
  String toString() => 'BackgroundTaskRef($id, $type)';
}

/// Claude's `Stop` / `SubagentStop` `background_tasks[]` snapshot: the
/// in-flight background work registered in the session at the moment the turn
/// paused ("lets hooks distinguish *session is done* from *session is paused
/// waiting for background work to wake it*").
///
/// Returns `null` when the payload carries no `background_tasks` key at all —
/// older claude builds and flashskyai do not send it, and callers must treat
/// "absent" as "unknown, leave existing state alone" rather than "empty".
/// An empty list is authoritative: nothing is in flight.
List<BackgroundTaskRef>? parseBackgroundTasks(Map<String, Object?> body) {
  final raw = body['background_tasks'];
  if (raw is! List) return null;
  final refs = <BackgroundTaskRef>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final id = (item['id']?.toString() ?? '').trim();
    if (id.isEmpty) continue;
    refs.add(
      BackgroundTaskRef(id: id, type: (item['type']?.toString() ?? '').trim()),
    );
  }
  return refs;
}

/// The `<task-id>` inside a `<task-notification>` [prompt], or null when
/// the prompt is anything else (real user input).
String? taskNotificationTaskId(String? prompt) {
  if (prompt == null) return null;
  final trimmed = prompt.trim();
  if (!trimmed.startsWith('<task-notification>')) return null;
  final match = RegExp(r'<task-id>\s*([^<]+?)\s*</task-id>').firstMatch(trimmed);
  return match?.group(1);
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
