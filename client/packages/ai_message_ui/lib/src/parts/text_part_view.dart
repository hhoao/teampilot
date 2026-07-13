import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Streaming-safe markdown text part.
///
/// Approach for unclosed fences: count ``` fence openers; when the count is
/// odd (streaming mid-fence), append a closing ``` so the markdown parser
/// always sees a well-formed document and does not thrash layout.
class AiTextPartView extends StatelessWidget {
  const AiTextPartView({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final data = _prepareStreamingMarkdown(text);
    return MarkdownBody(
      data: data,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
    );
  }
}

String _prepareStreamingMarkdown(String raw) {
  final fenceCount =
      RegExp(r'^```', multiLine: true).allMatches(raw).length;
  if (fenceCount.isOdd) {
    return '$raw\n```';
  }
  return raw;
}
