import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_font_resolver.dart';
import 'package:teampilot/theme/app_fonts.dart';
import 'package:teampilot/theme/app_markdown_style_sheet.dart';
import 'package:teampilot/theme/app_text_styles_warmup.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:tp_markdown/tp_markdown.dart';

void main() {
  test('markdown styles are covered by interactive warmup fingerprints', () {
    final fonts = AppFontResolver.resolve(
      uiFontId: 'system',
      monoFontId: 'jetbrainsMono',
      platform: TargetPlatform.linux,
    );
    final theme = bootstrapThemeForTextWarmup(fonts);
    final tokens = buildAppMarkdownTokens(
      theme,
      MarkdownProfile.document,
      width: TpBreakpoints.md,
    );
    final warmupKeys = TpGlyphWarmup.dedupeByShapeKey(
      textStylesForThemeWarmup(theme),
    ).map(TpGlyphWarmup.shapeKey).toSet();

    for (final style in appMarkdownTextStyles(theme)) {
      final key = TpGlyphWarmup.shapeKey(style);
      expect(
        warmupKeys.contains(key),
        isTrue,
        reason:
            'markdown style $key missing from warmup '
            '(family/size/weight/style must match a warmed TextStyle)',
      );
    }

    // Spot-check token fields still resolve to warmed styles.
    expect(warmupKeys.contains(TpGlyphWarmup.shapeKey(tokens.body)), isTrue);
    expect(warmupKeys.contains(TpGlyphWarmup.shapeKey(tokens.codeBlock)), isTrue);
    expect(
      warmupKeys.contains(
        TpGlyphWarmup.shapeKey(
          tokens.body.copyWith(fontStyle: FontStyle.italic),
        ),
      ),
      isTrue,
    );
    expect(
      warmupKeys.contains(
        TpGlyphWarmup.shapeKey(
          tokens.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      isTrue,
    );

    // Edit tool chrome: codeBlock (+ color only) and badge = codeLanguage + w600
    // (same shape as toolTrigger / smSemibold).
    expect(
      warmupKeys.contains(TpGlyphWarmup.shapeKey(tokens.codeBlock)),
      isTrue,
    );
    expect(
      warmupKeys.contains(
        TpGlyphWarmup.shapeKey(
          tokens.codeLanguage.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      isTrue,
      reason: 'edit +/- badges use toolTrigger (codeLanguage+w600); must stay in warmup',
    );
  });

  test('markdown code uses mono body size, not a unique scaled size', () {
    final fonts = AppFontResolver.resolve(
      uiFontId: 'system',
      monoFontId: 'jetbrainsMono',
      platform: TargetPlatform.linux,
    );
    final theme = buildLightTheme(
      null,
      AppTypographyScale.standard,
      null,
      fonts,
    );
    final tokens = buildAppMarkdownTokens(
      theme,
      MarkdownProfile.document,
      width: TpBreakpoints.md,
    );
    final mono = theme.extension<TpFontTheme>()!;
    final bodySize = theme.textTheme.bodyMedium!.fontSize;

    expect(tokens.inlineCode.fontFamily, mono.monoFontFamily);
    expect(tokens.inlineCode.fontSize, bodySize);
    expect(tokens.inlineCode.fontSize, isNot(bodySize! * 0.85));
  });

  test('warmMarkdownMixedInlineLayout primes nested inline paths', () {
    final fonts = AppFontResolver.resolve(
      uiFontId: 'system',
      monoFontId: 'jetbrainsMono',
      platform: TargetPlatform.linux,
    );
    final theme = bootstrapThemeForTextWarmup(fonts);
    warmMarkdownMixedInlineLayout(theme);
  });

  test('mixed inline warmup includes tableHead × mono', () {
    final fonts = AppFontResolver.resolve(
      uiFontId: 'system',
      monoFontId: 'jetbrainsMono',
      platform: TargetPlatform.linux,
    );
    final theme = bootstrapThemeForTextWarmup(fonts);
    final tokens = buildAppMarkdownTokens(
      theme,
      MarkdownProfile.document,
      width: TpBreakpoints.md,
    );
    final outers = markdownMixedCodeOuterStyles(tokens);
    final bold = tokens.strongStyle(tokens.body);

    // tableHead is mdSemibold (w600); StrongRun bold is w700 — distinct keys.
    expect(
      TpGlyphWarmup.shapeKey(tokens.tableHead),
      isNot(TpGlyphWarmup.shapeKey(bold)),
    );
    expect(
      outers.map(TpGlyphWarmup.shapeKey),
      contains(TpGlyphWarmup.shapeKey(tokens.tableHead)),
      reason:
          'table header cells with `code` use tableHead as outer; '
          'mix(bold) does not cover w600',
    );
  });
}
