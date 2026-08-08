/// Normalizes a user prompt for text comparisons.
///
/// Used by the seat's optimistic-pending rollback: a send that fails is undone
/// by matching the submitted text against the pending bubble, and landing seeds
/// are cancelled the same way.
String normalizeAiHistoryPendingText(String raw) =>
    raw.trim().replaceAll(RegExp(r'\s+'), ' ');
