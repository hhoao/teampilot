import 'package:flutter/material.dart';

import 'compiled_markdown_style.dart';

/// Chrome typography derived from host [CompiledMarkdownStyle] tokens.
extension CompiledMarkdownChrome on CompiledMarkdownStyle {
  TextStyle toolTrigger(
    Color color, {
    bool cancelled = false,
    double height = 1.2,
  }) {
    return codeLanguage.copyWith(
      color: color,
      fontWeight: FontWeight.w600,
      height: height,
      decoration: cancelled ? TextDecoration.lineThrough : null,
    );
  }

  TextStyle toolNameEmphasis(TextStyle base) =>
      base.copyWith(fontWeight: FontWeight.w700);

  TextStyle reasoningBody(Color onSurfaceVariant) =>
      blockquote.copyWith(color: onSurfaceVariant, height: 1.5);

  TextStyle systemMessage(Color onSurfaceVariant) =>
      blockquote.copyWith(color: onSurfaceVariant);

  TextStyle statusBanner(Color onErrorContainer) =>
      codeLanguage.copyWith(color: onErrorContainer);

  TextStyle userBubble(Color foreground) =>
      body.copyWith(color: foreground, height: 1.5);

  TextStyle assistantBody(Color onSurface) =>
      body.copyWith(color: onSurface);
}
