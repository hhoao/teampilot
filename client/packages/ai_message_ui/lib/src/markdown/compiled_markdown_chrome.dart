import 'package:flutter/material.dart';

import 'package:tp_markdown/tp_markdown.dart';

/// Chrome typography derived from host [MarkdownTokens].
extension MarkdownTokensChrome on MarkdownTokens {
  TextStyle toolTrigger(
    Color color, {
    bool cancelled = false,
    double height = 1.2,
  }) {
    return codeLanguage.copyWith(
      color: color,
      fontWeight: FontWeight.w600,
      height: height,
      leadingDistribution: TextLeadingDistribution.even,
      decoration: cancelled ? TextDecoration.lineThrough : null,
    );
  }

  /// Open-target label metrics aligned with [toolTrigger]. Keeps the same
  /// muted chrome as Agent titles (no primary/blue link styling).
  TextStyle toolFileLink(TextStyle trigger, Color color) => trigger.copyWith(
    color: color,
    decoration: trigger.decoration,
    decorationColor: color,
  );

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

  TextStyle assistantBody(Color onSurface) => body.copyWith(color: onSurface);
}
