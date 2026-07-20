import 'agent_attention_state.dart';

/// Classifies Cursor PTY OSC titles into permission attention.
///
/// Bare native title `"Cursor Agent"` is a no-op (null) — cursor-agent re-emits
/// it constantly and it carries no permission signal. Titles containing
/// `action required` / `permission` / `waiting` map to [AgentSeatAttention.waiting].
AgentSeatAttention? detectCursorTitleAttention(String title) {
  if (title.isEmpty) return null;
  final trimmed = title.trim();
  if (trimmed.toLowerCase() == 'cursor agent') return null;

  final lower = trimmed.toLowerCase();
  if (lower.contains('action required') ||
      lower.contains('permission') ||
      lower.contains('waiting')) {
    return AgentSeatAttention.waiting;
  }
  return null;
}

/// True when [title] is cursor-agent's bare native OSC title (case-insensitive).
bool isCursorNativeTitle(String title) =>
    title.trim().toLowerCase() == 'cursor agent';
