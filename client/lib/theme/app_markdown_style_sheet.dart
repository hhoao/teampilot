import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:tp_markdown/tp_markdown.dart';


/// Text styles [buildAppMarkdownTokens] paints — boot glyph warmup.
List<TextStyle> appMarkdownTextStyles(ThemeData theme) {
  return buildAppMarkdownTokens(theme, MarkdownProfile.document)
      .textStylesForWarmup;
}

/// Host [MarkdownTokens] bound to [TpTextStyles] + [TpFontTheme].
///
/// Uses only warmup-covered size/weight variants — no ad-hoc sizes that miss
/// the glyph cache. Install on [AiMessageTheme.markdown].
MarkdownTokens buildAppMarkdownTokens(
  ThemeData theme,
  MarkdownProfile profile, {
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
    h1Top,
    h2Top,
    h3Top,
    h4Top,
    h5Top,
    h6Top,
    paragraphGap,
    blockGap,
    ruleGap,
  ) = switch (profile) {
    MarkdownProfile.document => (
        40.0,
        36.0,
        32.0,
        28.0,
        28.0,
        28.0,
        16.0,
        28.0,
        28.0,
      ),
    MarkdownProfile.compact => (
        16.0,
        12.0,
        8.0,
        8.0,
        8.0,
        8.0,
        12.0,
        12.0,
        12.0,
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
    headingBottom: 8,
    paragraphGap: paragraphGap,
    blockGap: blockGap,
    listItemGap: 8,
    listIndent: 24,
    ruleGap: ruleGap,
    h1TopSpacing: h1Top,
    h2TopSpacing: h2Top,
    h3TopSpacing: h3Top,
    h4TopSpacing: h4Top,
    h5TopSpacing: h5Top,
    h6TopSpacing: h6Top,
  );
}

/// Default [AiMessageTheme] for the app shell; chat routes override layout tokens.
AiMessageTheme buildAppAiMessageTheme(ThemeData theme) {
  return AiMessageTheme(
    markdown: buildAppMarkdownTokens(theme, MarkdownProfile.compact),
  );
}

/// Boot layout paths for markdown preview that single-style warmup cannot
/// cover (nested inline styles in one [TextPainter]). Uses
/// [TpGlyphWarmup.styleProbe] only — finite style mixes, not document text.
///
/// Primes common IR nests: body/strong/emphasis × mono code, and strong ×
/// emphasis. Link [WidgetSpan]s are a separate mount cost (not shaped here).
void warmMarkdownMixedInlineLayout(ThemeData theme) {
  final tokens = buildAppMarkdownTokens(theme, MarkdownProfile.document);
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

