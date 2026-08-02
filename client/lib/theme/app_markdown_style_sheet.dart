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
          sm: EdgeInsets.only(top: 24, bottom: 8),
          xxl: EdgeInsets.only(top: 40, bottom: 8),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 22, bottom: 8),
          xxl: EdgeInsets.only(top: 36, bottom: 8),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 20, bottom: 8),
          xxl: EdgeInsets.only(top: 32, bottom: 8),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 18, bottom: 8),
          xxl: EdgeInsets.only(top: 28, bottom: 8),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 18, bottom: 8),
          xxl: EdgeInsets.only(top: 28, bottom: 8),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 18, bottom: 8),
          xxl: EdgeInsets.only(top: 28, bottom: 8),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(bottom: 12),
          xxl: EdgeInsets.only(bottom: 16),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(bottom: 16),
          xxl: EdgeInsets.only(bottom: 28),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(bottom: 16),
          xxl: EdgeInsets.only(bottom: 28),
        ).forWidth(width),
      ),
    MarkdownProfile.compact => (
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 12, bottom: 8),
          xxl: EdgeInsets.only(top: 16, bottom: 8),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 10, bottom: 8),
          xxl: EdgeInsets.only(top: 12, bottom: 8),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 6, bottom: 8),
          xxl: EdgeInsets.only(top: 8, bottom: 8),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 6, bottom: 8),
          xxl: EdgeInsets.only(top: 8, bottom: 8),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 6, bottom: 8),
          xxl: EdgeInsets.only(top: 8, bottom: 8),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(top: 6, bottom: 8),
          xxl: EdgeInsets.only(top: 8, bottom: 8),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(bottom: 8),
          xxl: EdgeInsets.only(bottom: 12),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(bottom: 8),
          xxl: EdgeInsets.only(bottom: 12),
        ).forWidth(width),
        const TpScaledEdgeInsets(
          sm: EdgeInsets.only(bottom: 8),
          xxl: EdgeInsets.only(bottom: 12),
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
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    tableHeadBackground: scheme.onSurface.withValues(alpha: 0.04),
    tableBodyBackground: Colors.transparent,
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
    tableMargin: blockMargin,
    horizontalRuleMargin: ruleMargin,
    imageMargin: blockMargin,
    rawLiteralMargin: blockMargin,
    listItemGap: 8,
    listIndent: 24,
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

/// Boot layout paths for markdown preview that single-style warmup cannot
/// cover (nested inline styles in one [TextPainter]). Uses
/// [TpGlyphWarmup.styleProbe] only — finite style mixes, not document text.
///
/// Primes common IR nests: body/strong/emphasis × mono code, and strong ×
/// emphasis. Link [WidgetSpan]s are a separate mount cost (not shaped here).
void warmMarkdownMixedInlineLayout(ThemeData theme) {
  final tokens = buildAppMarkdownTokens(
    theme,
    MarkdownProfile.document,
    width: TpBreakpoints.md, // warmup ignores margins
  );
  final body = tokens.body;
  final bold = body.copyWith(fontWeight: FontWeight.w700);
  final italic = body.copyWith(fontStyle: FontStyle.italic);
  final boldItalic = bold.copyWith(fontStyle: FontStyle.italic);
  final code = tokens.inlineCode;
  final strut = forcedStrut(body);
  const probe = TpGlyphWarmup.styleProbe;

  void mix(TextStyle outer) {
    final codeAtSize = code.copyWith(
      fontSize: outer.fontSize,
      height: outer.height,
      letterSpacing: outer.letterSpacing,
    );
    TpGlyphWarmup.shapeRich(
      text: TextSpan(
        style: outer,
        children: [
          TextSpan(text: probe, style: outer),
          TextSpan(text: 'x', style: codeAtSize),
          TextSpan(text: probe, style: outer),
        ],
      ),
      strutStyle: strut,
    );
  }

  // CodeRun merges mono chrome with surrounding size (see inline_spans).
  mix(body);
  mix(bold);
  mix(italic);
  mix(boldItalic);
  mix(tokens.h1);
  mix(tokens.h2);

  // StrongRun + EmphasisRun (no family switch).
  TpGlyphWarmup.shapeRich(
    text: TextSpan(
      style: bold,
      children: [
        TextSpan(text: probe, style: bold),
        TextSpan(text: probe, style: boldItalic),
        TextSpan(text: probe, style: bold),
      ],
    ),
    strutStyle: strut,
  );
}
