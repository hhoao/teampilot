import 'package:flutter/material.dart';

import '../ir/markdown_block_kind.dart';

/// Typography, chrome, and rhythm tokens for the semantic markdown renderer.
@immutable
class MarkdownTokens {
  const MarkdownTokens({
    required this.body,
    required this.h1,
    required this.h2,
    required this.h3,
    required this.h4,
    required this.h5,
    required this.h6,
    required this.link,
    required this.inlineCode,
    required this.codeBlock,
    required this.codeLanguage,
    required this.listBullet,
    required this.blockquote,
    required this.tableHead,
    required this.tableBody,
    required this.mutedSurface,
    required this.borderColor,
    required this.codeBlockRadius,
    required this.tableCellsPadding,
    required this.tableHeadBackground,
    required this.tableBodyBackground,
    required this.headingBottom,
    required this.paragraphGap,
    required this.blockGap,
    required this.listItemGap,
    required this.listIndent,
    required this.ruleGap,
    required this.h1TopSpacing,
    required this.h2TopSpacing,
    required this.h3TopSpacing,
    required this.h4TopSpacing,
    required this.h5TopSpacing,
    required this.h6TopSpacing,
  });

  /// Minimal tokens for package widget tests (not for product UI).
  factory MarkdownTokens.test({
    ColorScheme? scheme,
    double codeBlockRadius = 12,
    EdgeInsets? tableCellsPadding,
    Color? tableHeadBackground,
    Color? tableBodyBackground,
    double headingBottom = 8,
    double paragraphGap = 12,
    double blockGap = 12,
    double listItemGap = 4,
    double listIndent = 24,
    double ruleGap = 12,
    double h1TopSpacing = 16,
    double h2TopSpacing = 12,
    double h3TopSpacing = 8,
    double h4TopSpacing = 8,
    double h5TopSpacing = 8,
    double h6TopSpacing = 8,
  }) {
    final colors = scheme ?? const ColorScheme.light();
    const body = TextStyle(fontSize: 14, height: 1.4);
    const code = TextStyle(fontSize: 12, height: 1.45);
    final muted = colors.surfaceContainerHighest.withValues(alpha: 0.55);
    return MarkdownTokens(
      body: body,
      h1: body.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
      h2: body.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      h3: body.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      h4: body.copyWith(fontWeight: FontWeight.w600),
      h5: body.copyWith(fontWeight: FontWeight.w600),
      h6: body,
      link: body.copyWith(
        color: colors.primary,
        decoration: TextDecoration.underline,
        decorationColor: colors.primary,
      ),
      inlineCode: body.copyWith(backgroundColor: muted),
      codeBlock: code.copyWith(color: colors.onSurface),
      codeLanguage: code.copyWith(
        color: colors.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
      listBullet: body,
      blockquote: body.copyWith(color: colors.onSurfaceVariant),
      tableHead: body.copyWith(fontWeight: FontWeight.w600),
      tableBody: body,
      mutedSurface: muted,
      borderColor: colors.outlineVariant.withValues(alpha: 0.55),
      codeBlockRadius: codeBlockRadius,
      tableCellsPadding: tableCellsPadding ??
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      tableHeadBackground: tableHeadBackground,
      tableBodyBackground: tableBodyBackground ?? Colors.transparent,
      headingBottom: headingBottom,
      paragraphGap: paragraphGap,
      blockGap: blockGap,
      listItemGap: listItemGap,
      listIndent: listIndent,
      ruleGap: ruleGap,
      h1TopSpacing: h1TopSpacing,
      h2TopSpacing: h2TopSpacing,
      h3TopSpacing: h3TopSpacing,
      h4TopSpacing: h4TopSpacing,
      h5TopSpacing: h5TopSpacing,
      h6TopSpacing: h6TopSpacing,
    );
  }

  final TextStyle body;
  final TextStyle h1;
  final TextStyle h2;
  final TextStyle h3;
  final TextStyle h4;
  final TextStyle h5;
  final TextStyle h6;
  final TextStyle link;
  final TextStyle inlineCode;
  final TextStyle codeBlock;
  final TextStyle codeLanguage;
  final TextStyle listBullet;
  final TextStyle blockquote;
  final TextStyle tableHead;
  final TextStyle tableBody;
  final Color mutedSurface;
  final Color borderColor;
  final double codeBlockRadius;
  final EdgeInsets tableCellsPadding;
  final Color? tableHeadBackground;
  final Color tableBodyBackground;
  final double headingBottom;
  final double paragraphGap;
  final double blockGap;
  final double listItemGap;
  final double listIndent;
  final double ruleGap;
  final double h1TopSpacing;
  final double h2TopSpacing;
  final double h3TopSpacing;
  final double h4TopSpacing;
  final double h5TopSpacing;
  final double h6TopSpacing;

  double headingTop(int level) {
    return switch (level) {
      1 => h1TopSpacing,
      2 => h2TopSpacing,
      3 => h3TopSpacing,
      4 => h4TopSpacing,
      5 => h5TopSpacing,
      _ => h6TopSpacing,
    };
  }
}

bool _isHeading(MarkdownBlockKind kind) {
  return switch (kind) {
    MarkdownBlockKind.heading1 ||
    MarkdownBlockKind.heading2 ||
    MarkdownBlockKind.heading3 ||
    MarkdownBlockKind.heading4 ||
    MarkdownBlockKind.heading5 ||
    MarkdownBlockKind.heading6 =>
      true,
    _ => false,
  };
}

int _headingLevel(MarkdownBlockKind kind) {
  return switch (kind) {
    MarkdownBlockKind.heading1 => 1,
    MarkdownBlockKind.heading2 => 2,
    MarkdownBlockKind.heading3 => 3,
    MarkdownBlockKind.heading4 => 4,
    MarkdownBlockKind.heading5 => 5,
    MarkdownBlockKind.heading6 => 6,
    _ => throw ArgumentError.value(kind, 'kind', 'not a heading'),
  };
}

/// Inter-block vertical gap from [previous] to [next] block kinds.
double gapBetween(
  MarkdownBlockKind? previous,
  MarkdownBlockKind next,
  MarkdownTokens t,
) {
  if (previous == null) return 0;
  if (_isHeading(next)) return t.headingTop(_headingLevel(next));
  if (_isHeading(previous)) return t.headingBottom;
  if (previous == MarkdownBlockKind.paragraph &&
      next == MarkdownBlockKind.paragraph) {
    return t.paragraphGap;
  }
  if (previous == MarkdownBlockKind.horizontalRule ||
      next == MarkdownBlockKind.horizontalRule) {
    return t.ruleGap;
  }
  return t.blockGap;
}
