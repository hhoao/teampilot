import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'app_fonts.dart';
import 'app_text_styles.dart';

/// Text styles [buildAppMarkdownStyleSheet] paints — keep in sync for boot
/// glyph warmup ([textStylesForThemeWarmup]).
List<TextStyle> appMarkdownTextStyles(ThemeData theme) {
  final sheet = buildAppMarkdownStyleSheet(theme);
  return [
    sheet.p!,
    sheet.code!,
    sheet.h1!,
    sheet.h2!,
    sheet.h3!,
    sheet.h4!,
    sheet.h5!,
    sheet.h6!,
    sheet.em!,
    sheet.strong!,
    sheet.del!,
    sheet.blockquote!,
    sheet.listBullet!,
    sheet.a!,
    sheet.checkbox!,
    sheet.tableBody!,
    sheet.tableHead!,
  ];
}

/// Session-history (and shared) markdown styles bound to [AppFontTheme].
///
/// Uses only [AppTextStyles] variants (same size/weight as boot warmup) — no
/// unique scaled sizes like `fontSize * 0.85` that miss the glyph cache.
/// [MarkdownStyleSheet.fromTheme] hardcodes `monospace` for code; we replace
/// that with the app mono face + CJK fallbacks.
MarkdownStyleSheet buildAppMarkdownStyleSheet(ThemeData theme) {
  final fonts = theme.extension<AppFontTheme>() ?? AppFontTheme.fallback;
  final styles = AppTextStyles(theme);
  final scheme = theme.colorScheme;
  final base = MarkdownStyleSheet.fromTheme(theme);

  TextStyle withUi(TextStyle style) => style.copyWith(
    fontFamily: fonts.uiFontFamily,
    fontFamilyFallback: fonts.uiFontFamilyFallback,
  );

  final body = withUi(styles.body);
  final code = styles.mono.copyWith(
    backgroundColor: theme.cardTheme.color ?? theme.cardColor,
    fontFamily: fonts.monoFontFamily,
    fontFamilyFallback: fonts.monoFontFamilyFallback,
  );

  return base.copyWith(
    p: body,
    code: code,
    h1: withUi(styles.dialogTitle),
    h2: withUi(styles.subtitle),
    h3: withUi(styles.sectionTitle),
    h4: withUi(styles.prominent),
    h5: body,
    h6: body,
    em: body.copyWith(fontStyle: FontStyle.italic),
    strong: withUi(styles.bodyStrong),
    del: body.copyWith(decoration: TextDecoration.lineThrough),
    blockquote: withUi(styles.mutedBody),
    img: body,
    checkbox: body.copyWith(color: scheme.primary),
    listBullet: body,
    tableHead: withUi(styles.bodyStrong),
    tableBody: body,
    a: body.copyWith(color: scheme.primary),
  );
}
