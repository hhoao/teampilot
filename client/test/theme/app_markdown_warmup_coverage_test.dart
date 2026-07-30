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

void main() {
  test('markdown styles are covered by interactive warmup fingerprints', () {
    final fonts = AppFontResolver.resolve(
      uiFontId: 'system',
      monoFontId: 'jetbrainsMono',
      platform: TargetPlatform.linux,
    );
    final theme = bootstrapThemeForTextWarmup(fonts);
    final sheet = buildAppMarkdownStyleSheet(theme);
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

    // Spot-check sheet fields still resolve to those styles.
    expect(warmupKeys.contains(TpGlyphWarmup.shapeKey(sheet.p!)), isTrue);
    expect(warmupKeys.contains(TpGlyphWarmup.shapeKey(sheet.code!)), isTrue);
    expect(warmupKeys.contains(TpGlyphWarmup.shapeKey(sheet.em!)), isTrue);
    expect(warmupKeys.contains(TpGlyphWarmup.shapeKey(sheet.strong!)), isTrue);

    // Edit tool chrome: codeBlock (+ color only) and badge = codeLanguage + w600
    // (same shape as toolTrigger / smSemibold).
    final markdown = buildAppCompiledMarkdownStyle(theme);
    expect(
      warmupKeys.contains(TpGlyphWarmup.shapeKey(markdown.codeBlock)),
      isTrue,
    );
    expect(
      warmupKeys.contains(
        TpGlyphWarmup.shapeKey(
          markdown.codeLanguage.copyWith(fontWeight: FontWeight.w600),
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
    final sheet = buildAppMarkdownStyleSheet(theme);
    final mono = theme.extension<TpFontTheme>()!;
    final bodySize = theme.textTheme.bodyMedium!.fontSize;

    expect(sheet.code?.fontFamily, mono.monoFontFamily);
    expect(sheet.code?.fontSize, bodySize);
    expect(sheet.code?.fontSize, isNot(bodySize! * 0.85));
  });
}
