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
  double blockSpacing = 28,
  double listItemSpacing = 8,
}) {
  final fonts = theme.extension<TpFontTheme>() ?? TpFontTheme.fallback;
  final styles = TpTextStyles(theme);
  final scheme = theme.colorScheme;

  TextStyle withUi(TextStyle style) => style.copyWith(
    fontFamily: fonts.uiFontFamily,
    fontFamilyFallback: fonts.uiFontFamilyFallback,
  );

  final body = withUi(styles.mdRelaxed.copyWith(height: 1.7));
  final muted =
      mutedSurface ?? scheme.surfaceContainerHighest.withValues(alpha: 0.55);
  final inlineCode = body.copyWith(
    fontFamily: fonts.monoFontFamily,
    fontFamilyFallback: fonts.monoFontFamilyFallback,
  );
  final codeBlock = styles.mono.copyWith(color: scheme.onSurface);

  return CompiledMarkdownStyle(
    body: body,
    // Size ladder (Material text theme): display → xl → lg → md.
    // Prefer warmup-covered TpTextStyles tokens over ad-hoc fontSize.
    h1: withUi(
      styles.display.copyWith(height: 1.3, letterSpacing: -0.02),
    ),
    h2: withUi(styles.xl.copyWith(height: 1.3)),
    h3: withUi(styles.lgSemiboldSnug.copyWith(height: 1.3)),
    h4: withUi(styles.lgSnug.copyWith(height: 1.3)),
    h5: withUi(styles.mdSemiboldTightSnug.copyWith(height: 1.3)),
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
    blockquote: withUi(
      styles.mdRelaxed.copyWith(
        color: scheme.onSurfaceVariant,
        height: 1.7,
      ),
    ),
    tableHead: withUi(styles.mdSemibold),
    tableBody: body,
    mutedSurface: muted,
    borderColor: scheme.outlineVariant.withValues(alpha: 0.45),
    codeBlockRadius: codeBlockRadius,
    blockSpacing: blockSpacing,
    listItemSpacing: listItemSpacing,
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    tableHeadBackground: scheme.onSurface.withValues(alpha: 0.04),
    tableBodyBackground: Colors.transparent,
    h1TopSpacing: 40,
    h2TopSpacing: 36,
    h3TopSpacing: 32,
    h4TopSpacing: 28,
    h5TopSpacing: 28,
    h6TopSpacing: 28,
    headingBottomSpacing: 8,
  );
}

/// [MarkdownBody] / file-preview sheet derived from the compiled host styles.
MarkdownStyleSheet buildAppMarkdownStyleSheet(ThemeData theme) {
  return buildAppCompiledMarkdownStyle(theme).toMarkdownStyleSheet();
}

/// Default [AiMessageTheme] for the app shell; chat routes override layout tokens.
AiMessageTheme buildAppAiMessageTheme(ThemeData theme) {
  return AiMessageTheme(markdown: buildAppCompiledMarkdownStyle(theme));
}
