/// Distinctive grid substring for full-screen PTY automation ACK probes.
abstract final class PtyAutomationNeedle {
  PtyAutomationNeedle._();

  static const busTag = '[teammate-bus]';
  static const maxNeedleChars = 40;

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
}
