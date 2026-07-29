import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

/// Syntax highlighter for a single edit diff line.
abstract class AiEditLineHighlighter {
  const AiEditLineHighlighter();

  InlineSpan highlight({
    required String path,
    required String text,
    required AiEditLineKind kind,
    required TextStyle baseStyle,
  });
}

/// Default highlighter — plain monospace text with no token colors.
class PlainEditLineHighlighter extends AiEditLineHighlighter {
  const PlainEditLineHighlighter();

  @override
  InlineSpan highlight({
    required String path,
    required String text,
    required AiEditLineKind kind,
    required TextStyle baseStyle,
  }) {
    return TextSpan(text: text, style: baseStyle);
  }
}
