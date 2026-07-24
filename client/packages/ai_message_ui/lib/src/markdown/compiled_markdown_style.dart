import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Typography + chrome for [CompiledTextPartView].
///
/// Host apps build this from their design-system / glyph-warmup styles
/// and install it on [AiMessageTheme].
/// The package does not invent ad-hoc sizes or font families.
@immutable
class CompiledMarkdownStyle {
  const CompiledMarkdownStyle({
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
    this.blockSpacing = 12,
    this.listIndent = 24,
  });

  /// Minimal styles for package widget tests (not for product UI).
  factory CompiledMarkdownStyle.test({
    ColorScheme? scheme,
    double codeBlockRadius = 12,
  }) {
    final colors = scheme ?? const ColorScheme.light();
    const body = TextStyle(fontSize: 14, height: 1.4);
    const code = TextStyle(fontSize: 12, height: 1.45);
    final muted = colors.surfaceContainerHighest.withValues(alpha: 0.55);
    return CompiledMarkdownStyle(
      body: body,
      h1: body.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
      h2: body.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      h3: body.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      h4: body.copyWith(fontWeight: FontWeight.w600),
      h5: body.copyWith(fontWeight: FontWeight.w600),
      h6: body.copyWith(fontWeight: FontWeight.w600),
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
  final double blockSpacing;
  final double listIndent;

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
      ];

  /// [MarkdownBody] fallback for unsupported IR slices — derived from this
  /// single source so hosts never maintain a second stylesheet.
  MarkdownStyleSheet toMarkdownStyleSheet() {
    return MarkdownStyleSheet(
      p: body,
      h1: h1,
      h2: h2,
      h3: h3,
      h4: h4,
      h5: h5,
      h6: h6,
      a: link,
      code: inlineCode,
      em: body.copyWith(fontStyle: FontStyle.italic),
      strong: body.copyWith(fontWeight: FontWeight.w600),
      del: body.copyWith(decoration: TextDecoration.lineThrough),
      listBullet: listBullet,
      blockquote: blockquote,
      tableHead: tableHead,
      tableBody: tableBody,
      checkbox: body,
      blockSpacing: blockSpacing,
      listIndent: listIndent,
      h1Padding: const EdgeInsets.only(top: 8),
      h2Padding: const EdgeInsets.only(top: 8),
      h3Padding: const EdgeInsets.only(top: 4),
      codeblockDecoration: BoxDecoration(
        color: mutedSurface,
        borderRadius: BorderRadius.circular(codeBlockRadius),
      ),
      codeblockPadding: EdgeInsets.zero,
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: borderColor, width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12),
      tableHeadAlign: TextAlign.start,
      tableBorder: TableBorder.all(color: borderColor, width: 1),
      tableColumnWidth: const IntrinsicColumnWidth(),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      tableHeadCellsDecoration: BoxDecoration(
        color: mutedSurface.withValues(alpha: 0.85),
      ),
      tableCellsDecoration: const BoxDecoration(),
      tablePadding: const EdgeInsets.symmetric(vertical: 8),
    );
  }
}
