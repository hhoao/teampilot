import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:shared_ui/shared_ui.dart';

/// Text styles [buildAppCompiledMarkdownStyle] paints — boot glyph warmup.
List<TextStyle> appMarkdownTextStyles(ThemeData theme) {
  return buildAppCompiledMarkdownStyle(theme).textStylesForWarmup;
}

/// Host [CompiledMarkdownStyle] bound to [TpTextStyles] + [TpFontTheme].
///
/// Uses only warmup-covered size/weight variants — no ad-hoc sizes that miss
/// the glyph cache. Install on [AiMessageTheme.markdown].
CompiledMarkdownStyle buildAppCompiledMarkdownStyle(
  ThemeData theme, {
  Color? mutedSurface,
  double codeBlockRadius = 12,
}) {
  final fonts = theme.extension<TpFontTheme>() ?? TpFontTheme.fallback;
  final styles = TpTextStyles(theme);
  final scheme = theme.colorScheme;

  TextStyle withUi(TextStyle style) => style.copyWith(
    fontFamily: fonts.uiFontFamily,
    fontFamilyFallback: fonts.uiFontFamilyFallback,
  );

  final body = withUi(styles.md);
  final muted = mutedSurface ??
      scheme.surfaceContainerHighest.withValues(alpha: 0.55);
  final inlineCode = body.copyWith(
    fontFamily: fonts.monoFontFamily,
    fontFamilyFallback: fonts.monoFontFamilyFallback,
    backgroundColor: muted.withValues(alpha: 0.55),
  );
  final codeBlock = styles.mono.copyWith(color: scheme.onSurface);

  return CompiledMarkdownStyle(
    body: body,
    h1: withUi(styles.lgSemiboldSnug),
    h2: withUi(styles.lgSnug),
    h3: withUi(styles.mdSemiboldTightSnug),
    h4: withUi(styles.lg),
    h5: body,
    h6: body,
    link: body.copyWith(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary,
    ),
    inlineCode: inlineCode,
    codeBlock: codeBlock,
    codeLanguage: withUi(styles.mutedSm),
    listBullet: body,
    blockquote: withUi(styles.mutedMd),
    tableHead: withUi(styles.mdSemibold),
    tableBody: body,
    mutedSurface: muted,
    borderColor: scheme.outlineVariant.withValues(alpha: 0.55),
    codeBlockRadius: codeBlockRadius,
  );
}

/// [MarkdownBody] / file-preview sheet derived from the compiled host styles.
MarkdownStyleSheet buildAppMarkdownStyleSheet(ThemeData theme) {
  return buildAppCompiledMarkdownStyle(theme).toMarkdownStyleSheet();
}

/// Default [AiMessageTheme] for the app shell; chat routes override layout tokens.
AiMessageTheme buildAppAiMessageTheme(ThemeData theme) {
  return AiMessageTheme(
    markdown: buildAppCompiledMarkdownStyle(theme),
  );
}
