import 'dart:math' as math;

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
    required this.paragraphMargin,
    required this.h1Margin,
    required this.h2Margin,
    required this.h3Margin,
    required this.h4Margin,
    required this.h5Margin,
    required this.h6Margin,
    required this.listMargin,
    required this.blockquoteMargin,
    required this.codeMargin,
    required this.tableMargin,
    required this.horizontalRuleMargin,
    required this.imageMargin,
    required this.rawLiteralMargin,
    required this.listItemGap,
    required this.listIndent,
    this.strongWeight = FontWeight.w700,
    this.emphasisFontStyle = FontStyle.italic,
    this.strikeDecoration = TextDecoration.lineThrough,
    this.matchHighlightColor = const Color(0x2690CAF9),
    this.matchHighlightActiveColor = const Color(0x66FFB74D),
  });

  /// Minimal tokens for package widget tests (not for product UI).
  factory MarkdownTokens.test({
    ColorScheme? scheme,
    double codeBlockRadius = 12,
    EdgeInsets? tableCellsPadding,
    Color? tableHeadBackground,
    Color? tableBodyBackground,
    EdgeInsets? paragraphMargin,
    EdgeInsets? h1Margin,
    EdgeInsets? h2Margin,
    EdgeInsets? h3Margin,
    EdgeInsets? h4Margin,
    EdgeInsets? h5Margin,
    EdgeInsets? h6Margin,
    EdgeInsets? listMargin,
    EdgeInsets? blockquoteMargin,
    EdgeInsets? codeMargin,
    EdgeInsets? tableMargin,
    EdgeInsets? horizontalRuleMargin,
    EdgeInsets? imageMargin,
    EdgeInsets? rawLiteralMargin,
    double listItemGap = 4,
    double listIndent = 24,
    FontWeight strongWeight = FontWeight.w700,
    FontStyle emphasisFontStyle = FontStyle.italic,
    TextDecoration strikeDecoration = TextDecoration.lineThrough,
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
      paragraphMargin:
          paragraphMargin ?? const EdgeInsets.only(bottom: 12),
      h1Margin: h1Margin ?? const EdgeInsets.only(top: 16, bottom: 8),
      h2Margin: h2Margin ?? const EdgeInsets.only(top: 12, bottom: 8),
      h3Margin: h3Margin ?? const EdgeInsets.only(top: 8, bottom: 8),
      h4Margin: h4Margin ?? const EdgeInsets.only(top: 8, bottom: 8),
      h5Margin: h5Margin ?? const EdgeInsets.only(top: 8, bottom: 8),
      h6Margin: h6Margin ?? const EdgeInsets.only(top: 8, bottom: 8),
      listMargin: listMargin ?? const EdgeInsets.only(bottom: 12),
      blockquoteMargin: blockquoteMargin ?? const EdgeInsets.only(bottom: 12),
      codeMargin: codeMargin ?? const EdgeInsets.only(bottom: 12),
      tableMargin: tableMargin ?? const EdgeInsets.symmetric(vertical: 12),
      horizontalRuleMargin:
          horizontalRuleMargin ?? const EdgeInsets.only(bottom: 12),
      imageMargin: imageMargin ?? const EdgeInsets.only(bottom: 12),
      rawLiteralMargin: rawLiteralMargin ?? const EdgeInsets.only(bottom: 12),
      listItemGap: listItemGap,
      listIndent: listIndent,
      strongWeight: strongWeight,
      emphasisFontStyle: emphasisFontStyle,
      strikeDecoration: strikeDecoration,
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
  final EdgeInsets paragraphMargin;
  final EdgeInsets h1Margin;
  final EdgeInsets h2Margin;
  final EdgeInsets h3Margin;
  final EdgeInsets h4Margin;
  final EdgeInsets h5Margin;
  final EdgeInsets h6Margin;
  final EdgeInsets listMargin;
  final EdgeInsets blockquoteMargin;
  final EdgeInsets codeMargin;
  final EdgeInsets tableMargin;
  final EdgeInsets horizontalRuleMargin;
  final EdgeInsets imageMargin;
  final EdgeInsets rawLiteralMargin;
  final double listItemGap;
  final double listIndent;

  /// [StrongRun] weight applied onto the surrounding base.
  final FontWeight strongWeight;

  /// [EmphasisRun] style applied onto the surrounding base.
  final FontStyle emphasisFontStyle;

  /// [StrikeRun] decoration applied onto the surrounding base.
  final TextDecoration strikeDecoration;

  /// Background wash painted over non-active search matches.
  final Color matchHighlightColor;

  /// Background wash painted over the active (navigated) search match.
  final Color matchHighlightActiveColor;

  EdgeInsets marginOf(MarkdownBlockKind kind) {
    return switch (kind) {
      MarkdownBlockKind.paragraph => paragraphMargin,
      MarkdownBlockKind.heading1 => h1Margin,
      MarkdownBlockKind.heading2 => h2Margin,
      MarkdownBlockKind.heading3 => h3Margin,
      MarkdownBlockKind.heading4 => h4Margin,
      MarkdownBlockKind.heading5 => h5Margin,
      MarkdownBlockKind.heading6 => h6Margin,
      MarkdownBlockKind.list => listMargin,
      MarkdownBlockKind.blockquote => blockquoteMargin,
      MarkdownBlockKind.code => codeMargin,
      MarkdownBlockKind.table => tableMargin,
      MarkdownBlockKind.horizontalRule => horizontalRuleMargin,
      MarkdownBlockKind.image => imageMargin,
      MarkdownBlockKind.rawLiteral => rawLiteralMargin,
      // HTML blocks inherit the paragraph rhythm so surrounding gaps match.
      MarkdownBlockKind.html => paragraphMargin,
    };
  }

  TextStyle headingStyle(int level) {
    return switch (level) {
      1 => h1,
      2 => h2,
      3 => h3,
      4 => h4,
      5 => h5,
      _ => h6,
    };
  }

  /// [StrongRun] mark — host glyph warmup must use the same helper.
  TextStyle strongStyle(TextStyle base) =>
      base.copyWith(fontWeight: strongWeight);

  /// [EmphasisRun] mark — host glyph warmup must use the same helper.
  TextStyle emphasisStyle(TextStyle base) =>
      base.copyWith(fontStyle: emphasisFontStyle);

  /// [StrikeRun] mark — host glyph warmup must use the same helper.
  TextStyle strikeStyle(TextStyle base) =>
      base.copyWith(decoration: strikeDecoration);

  /// [CodeRun] paint style: mono/chrome from [inlineCode], metrics from [base].
  ///
  /// Headings and other outer roles keep their size/height so
  /// `# Title \`code\`` does not fall back to body-sized mono.
  TextStyle inlineCodeAt(TextStyle base) => inlineCode.copyWith(
        fontSize: base.fontSize,
        height: base.height,
        letterSpacing: base.letterSpacing,
      );

  /// Search-match paint over [base]: background wash only; [active] stronger.
  TextStyle matchHighlight(TextStyle base, {required bool active}) =>
      base.copyWith(
        backgroundColor:
            active ? matchHighlightActiveColor : matchHighlightColor,
      );

  /// Text styles that should participate in host glyph warmup.
  List<TextStyle> get textStylesForWarmup => [
        body,
        h1,
        h2,
        h3,
        h4,
        h5,
        h6,
        link,
        inlineCode,
        codeBlock,
        codeLanguage,
        listBullet,
        blockquote,
        tableHead,
        tableBody,
        // Mark-derived fingerprints track [strongWeight] / emphasis changes.
        strongStyle(body),
        emphasisStyle(body),
        emphasisStyle(strongStyle(body)),
      ];
}

/// Inter-block vertical gap from [previous] to [next] block kinds.
double gapBetween(
  MarkdownBlockKind? previous,
  MarkdownBlockKind next,
  MarkdownTokens t,
) {
  if (previous == null) return 0;
  final prevBottom = t.marginOf(previous).bottom;
  final nextTop = t.marginOf(next).top;
  return math.max(prevBottom, nextTop);
}
