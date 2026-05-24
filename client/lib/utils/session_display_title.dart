/// Derives a sidebar title from the user's first submitted prompt.
String deriveSessionTitleFromFirstPrompt(
  String prompt, {
  int maxLength = 48,
}) {
  final firstLine = prompt
      .split(RegExp(r'[\r\n]+'))
      .first
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (firstLine.isEmpty) return '';

  if (firstLine.length <= maxLength) return firstLine;
  if (maxLength <= 1) return firstLine.substring(0, maxLength);
  return '${firstLine.substring(0, maxLength - 1)}…';
}
