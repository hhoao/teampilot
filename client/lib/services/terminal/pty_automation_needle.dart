/// Distinctive grid substring for full-screen PTY automation ACK probes.
abstract final class PtyAutomationNeedle {
  PtyAutomationNeedle._();

  static const busTag = '[teammate-bus]';
  static const maxNeedleChars = 40;

  /// Claude Code collapses long staged pastes to composer chrome like
  /// `[Pasted text #3 +17 lines]` (body hidden until paste-again expand).
  static final collapsedPastePattern = RegExp(
    r'\[Pasted text #\d+ \+\d+ lines?\]',
  );

  /// Doorbell lines use a stable prefix; short landing text (e.g. CJK) fits whole;
  /// long free-form text falls back to the tail where the cursor usually sits.
  static String forText(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith(busTag)) {
      return trimmed.length <= maxNeedleChars
          ? trimmed
          : trimmed.substring(0, maxNeedleChars);
    }
    if (trimmed.length <= maxNeedleChars) return trimmed;
    return trimmed.substring(trimmed.length - maxNeedleChars);
  }

  /// Returns the Claude collapsed-paste chrome substring, or null.
  static String? collapsedPasteNeedle(String haystack) =>
      collapsedPastePattern.firstMatch(haystack)?.group(0);
}
