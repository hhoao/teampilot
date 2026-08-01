/// Streaming-safe fence repair shared by text parts and the content compiler.
String prepareStreamingMarkdown(String raw) {
  // Match line-start fences including indented ones (CommonMark-ish).
  final fenceCount =
      RegExp(r'^[ \t]{0,3}```', multiLine: true).allMatches(raw).length;
  if (fenceCount.isOdd) {
    return '$raw\n```';
  }
  return raw;
}
