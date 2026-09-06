/// Streaming-safe fence repair shared by text parts and the content compiler.
String prepareStreamingMarkdown(String raw) {
  // Match line-start fences including indented ones (CommonMark-ish).
  final fenceCount =
      RegExp(r'^[ \t]{0,3}```', multiLine: true).allMatches(raw).length;
  var out = raw;
  if (fenceCount.isOdd) {
    out = '$out\n```';
  }
  // dart `markdown` merges `</div>\n## Heading` into one raw HTML text node
  // when no blank line separates them (GFM authors often omit it). Insert a
  // blank line so the heading compiles as [HeadingBlock] and badge hoisting
  // cannot reorder past it.
  out = out.replaceAllMapped(
    RegExp(
      r'(</(?:div|p|section|article|header|footer|main|aside|nav|table|ul|ol|blockquote)>)\r?\n(#{1,6}\s)',
      caseSensitive: false,
    ),
    (m) => '${m[1]}\n\n${m[2]}',
  );
  return out;
}
