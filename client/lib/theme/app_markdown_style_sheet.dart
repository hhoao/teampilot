import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:tp_markdown/tp_markdown.dart';

/// Text styles [buildAppMarkdownTokens] paints — boot glyph warmup.
List<TextStyle> appMarkdownTextStyles(ThemeData theme) {
  return buildAppMarkdownTokens(
    theme,
    MarkdownProfile.document,
    width: TpBreakpoints.md, // warmup ignores margins
  ).textStylesForWarmup;
}

/// Host [MarkdownTokens] bound to [TpTextStyles] + [TpFontTheme].
///
/// Uses only warmup-covered size/weight variants — no ad-hoc sizes that miss
/// the glyph cache. Install on [AiMessageTheme.markdown].
MarkdownTokens buildAppMarkdownTokens(
  ThemeData theme,
  MarkdownProfile profile, {
  required double width,
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

  final body = withUi(styles.mdRelaxed.copyWith(height: 1.7));
  final muted =
      mutedSurface ?? scheme.surfaceContainerHighest.withValues(alpha: 0.55);
  final inlineCode = body.copyWith(
    fontFamily: fonts.monoFontFamily,
    fontFamilyFallback: fonts.monoFontFamilyFallback,
  );
  final codeBlock = styles.mono.copyWith(color: scheme.onSurface);

  final (
    h1Margin,
    h2Margin,
    h3Margin,
    h4Margin,
    h5Margin,
    h6Margin,
    paragraphMargin,
    blockMargin,
    ruleMargin,
  ) = switch (profile) {
    MarkdownProfile.document => (
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 26, bottom: 10),
          xxl: EdgeInsets.only(top: 42, bottom: 10),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 24, bottom: 10),
          xxl: EdgeInsets.only(top: 38, bottom: 10),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 22, bottom: 10),
          xxl: EdgeInsets.only(top: 34, bottom: 10),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 20, bottom: 10),
          xxl: EdgeInsets.only(top: 30, bottom: 10),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 20, bottom: 10),
          xxl: EdgeInsets.only(top: 30, bottom: 10),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 20, bottom: 10),
          xxl: EdgeInsets.only(top: 30, bottom: 10),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(bottom: 14),
          xxl: EdgeInsets.only(bottom: 18),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(bottom: 18),
          xxl: EdgeInsets.only(bottom: 30),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(bottom: 18),
          xxl: EdgeInsets.only(bottom: 30),
        ).forWidth(width),
      ),
    MarkdownProfile.compact => (
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 14, bottom: 10),
          xxl: EdgeInsets.only(top: 18, bottom: 10),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 12, bottom: 10),
          xxl: EdgeInsets.only(top: 14, bottom: 10),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 8, bottom: 10),
          xxl: EdgeInsets.only(top: 10, bottom: 10),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 8, bottom: 10),
          xxl: EdgeInsets.only(top: 10, bottom: 10),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 8, bottom: 10),
          xxl: EdgeInsets.only(top: 10, bottom: 10),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 8, bottom: 10),
          xxl: EdgeInsets.only(top: 10, bottom: 10),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(bottom: 10),
          xxl: EdgeInsets.only(bottom: 14),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(bottom: 10),
          xxl: EdgeInsets.only(bottom: 14),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(bottom: 10),
          xxl: EdgeInsets.only(bottom: 14),
        ).forWidth(width),
      ),
  };

  return MarkdownTokens(
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
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    tableHeadBackground: scheme.onSurface.withValues(alpha: 0.04),
    tableBodyBackground: Colors.transparent,
    // Search match washes (preview find): quiet primary tint for hits, stronger
    // wash for the active one.
    matchHighlightColor: scheme.primary.withValues(alpha: 0.20),
    matchHighlightActiveColor: scheme.primary.withValues(alpha: 0.45),
    paragraphMargin: paragraphMargin,
    h1Margin: h1Margin,
    h2Margin: h2Margin,
    h3Margin: h3Margin,
    h4Margin: h4Margin,
    h5Margin: h5Margin,
    h6Margin: h6Margin,
    listMargin: blockMargin,
    blockquoteMargin: blockMargin,
    codeMargin: blockMargin,
    // Table chrome: equal top/bottom so heading→table isn't glued (collapse
    // uses max(heading.bottom, table.top); top:0 left only 8px).
    tableMargin: EdgeInsets.only(
      top: blockMargin.bottom,
      bottom: blockMargin.bottom,
    ),
    horizontalRuleMargin: ruleMargin,
    imageMargin: blockMargin,
    rawLiteralMargin: blockMargin,
    listItemGap: 10,
    listIndent: 26,
    // Mark policy from TpTextStyles scale (not raw FontWeight literals).
    strongWeight: styles.mdBold.fontWeight!,
    emphasisFontStyle: FontStyle.italic,
    strikeDecoration: TextDecoration.lineThrough,
  );
}

/// Default [AiMessageTheme] for the app shell; chat routes override layout tokens.
AiMessageTheme buildAppAiMessageTheme(ThemeData theme) {
  return AiMessageTheme(
    markdown: buildAppMarkdownTokens(
      theme,
      MarkdownProfile.compact,
      width: TpBreakpoints.md, // warmup ignores margins
    ),
  );
}

