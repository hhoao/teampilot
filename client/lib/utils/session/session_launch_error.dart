import '../../services/terminal/terminal_startup_failure_detector.dart';

/// Soft ceiling so a pathological stderr dump cannot freeze the compose card.
/// Expandable details are scrollable; this is only a safety bound.
const kSessionLaunchErrorMaxDetailLines = 200;

/// Formats raw terminal / launch errors for the session failure card.
///
/// Normalizes whitespace and rewrites known linker failures. Keeps the full
/// detail text (up to [kSessionLaunchErrorMaxDetailLines]) so "View details"
/// can show the complete log — do not silently trim to a 4-line preview.
String formatSessionLaunchError(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return text;

  if (text == 'mixed_workspace_member_placement_uninitialized' ||
      text == 'lead_placement_invalid') {
    return 'Member placement is not ready for this mixed workspace.';
  }

  if (TerminalStartupFailureDetector.looksLikeGlibcIncompatibility(text)) {
    return TerminalStartupFailureDetector.classifyStartupFailure(
          text,
          executable: '',
          validateLaunch: false,
        ) ??
        text;
  }

  if (text.startsWith('[') && text.endsWith(']')) {
    text = text.substring(1, text.length - 1).trim();
  }

  final lines = text
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map((line) => line.replaceFirst(RegExp(r'^  +'), ''))
      .toList(growable: false);

  if (lines.isEmpty) return text;
  if (lines.length <= kSessionLaunchErrorMaxDetailLines) {
    return lines.join('\n');
  }
  return '${lines.take(kSessionLaunchErrorMaxDetailLines).join('\n')}\n…';
}
