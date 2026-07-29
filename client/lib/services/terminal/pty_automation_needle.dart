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
  ///
  /// CR/LF are flattened: the mirror grid never stores newlines as cells, so a
  /// raw multiline tail (common for long JSON pastes) can never ACK.
  static String forText(String text) {
    final trimmed = text.trim();
    final flat = trimmed.replaceAll(RegExp(r'[\r\n]+'), ' ');
    if (flat.startsWith(busTag)) {
      return flat.length <= maxNeedleChars
          ? flat
          : flat.substring(0, maxNeedleChars);
    }
    if (flat.length <= maxNeedleChars) return flat;
    return flat.substring(flat.length - maxNeedleChars);
  }

  /// Returns the Claude collapsed-paste chrome substring, or null.
  static String? collapsedPasteNeedle(String haystack) =>
      collapsedPastePattern.firstMatch(haystack)?.group(0);
}
