/// Formats raw terminal / launch errors for the session placeholder (P0).
String formatSessionLaunchError(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return text;

  if (text == 'mixed_workspace_member_targets_incomplete') {
    return 'Member assignments are incomplete for this mixed workspace.';
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

  const maxLines = 4;
  if (lines.length <= maxLines) {
    return lines.join('\n');
  }
  return '${lines.take(maxLines).join('\n')}\n…';
}
