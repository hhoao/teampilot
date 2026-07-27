import 'dart:io';

/// Compact stderr for git failures; skips clone progress lines.
String gitProcessStderrSnippet(
  ProcessResult result, {
  int maxLines = 3,
  int maxChars = 400,
}) {
  final err = result.stderr?.toString().trim() ?? '';
  if (err.isEmpty) return 'exit ${result.exitCode}';
  final useful = err
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .where((l) => !_isCloneProgressLine(l))
      .take(maxLines)
      .toList();
  final text = useful.isEmpty ? err.split('\n').first.trim() : useful.join('\n');
  return text.length > maxChars ? '${text.substring(0, maxChars)}…' : text;
}

bool _isCloneProgressLine(String line) {
  final lower = line.toLowerCase();
  return lower.startsWith('cloning into ') || line.startsWith('正克隆到');
}
