String buildFileAiContextClipboardText({
  required String relPath,
  required int startLine,
  required int endLine,
  required String language,
  required String code,
}) {
  return '$relPath:$startLine-$endLine\n```$language\n$code\n```';
}

String buildTerminalAiContextClipboardText({
  required String surfaceLabel,
  required String text,
  int? startLine,
  int? endLine,
}) {
  final body = text.trimRight();
  if (body.trim().isEmpty) return '';
  final range = (startLine != null && endLine != null)
      ? ' L$startLine-$endLine'
      : '';
  return 'terminal:$surfaceLabel$range\n```text\n$body\n```';
}

String selectionAskAiPrefillText(String aiContext) {
  final trimmed = aiContext.trimRight();
  if (trimmed.trim().isEmpty) return '';
  return '$trimmed\n\n';
}
