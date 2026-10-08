/// Active `@` or `/` token at the compose cursor.
enum ComposeTriggerKind { fileReference, slashInvoke }

class ComposeTriggerQuery {
  const ComposeTriggerQuery({
    required this.kind,
    required this.query,
    required this.triggerStart,
    required this.triggerEnd,
  });

  final ComposeTriggerKind kind;
  final String query;
  final int triggerStart;
  final int triggerEnd;
}

/// Returns the in-progress `@path` or `/name` token touching [cursorOffset].
///
/// [additionalSlashTriggers] are extra single-character prefixes that open the
/// slash menu alongside `/` (e.g. `$` when the target CLI is Codex).
ComposeTriggerQuery? detectComposeTrigger(
  String text,
  int cursorOffset, {
  Set<String> additionalSlashTriggers = const {},
}) {
  if (cursorOffset < 0 || cursorOffset > text.length) return null;

  final before = text.substring(0, cursorOffset);
  final tokenStart = _lastTokenBoundary(before);
  final token = before.substring(tokenStart);
  if (token.isEmpty) return null;

  final trigger = token[0];
  final isSlashTrigger =
      trigger == '/' || additionalSlashTriggers.contains(trigger);
  if (trigger != '@' && !isSlashTrigger) return null;

  final query = token.substring(1);
  if (query.contains(RegExp(r'\s')) || query.contains(trigger)) return null;

  return ComposeTriggerQuery(
    kind: trigger == '@'
        ? ComposeTriggerKind.fileReference
        : ComposeTriggerKind.slashInvoke,
    query: query,
    triggerStart: tokenStart,
    triggerEnd: cursorOffset,
  );
}

int _lastTokenBoundary(String before) {
  for (var i = before.length - 1; i >= 0; i--) {
    final ch = before[i];
    if (ch == ' ' || ch == '\n' || ch == '\t') return i + 1;
  }
  return 0;
}
