import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_font_resolver.dart';
import 'package:teampilot/theme/app_fonts.dart';
import 'package:teampilot/theme/app_markdown_style_sheet.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  ThemeData themeForTest() {
    final fonts = AppFontResolver.resolve(
      uiFontId: 'system',
      monoFontId: 'jetbrainsMono',
      platform: TargetPlatform.linux,
    );
    return buildLightTheme(
      null,
      AppTypographyScale.standard,
      null,
      fonts,
    );
  }

  test('document profile exposes Orca-like rhythm', () {
    final theme = themeForTest();
    final tokens = buildAppMarkdownTokens(theme, MarkdownProfile.document);
    final mono = theme.extension<TpFontTheme>()!;

    expect(tokens.body.height, 1.7);
    expect(tokens.blockquote.height, 1.7);
    expect(tokens.inlineCode.fontFamily, mono.monoFontFamily);
    expect(tokens.inlineCode.fontFamilyFallback, mono.monoFontFamilyFallback);
    expect(tokens.inlineCode.fontFamily, isNot('monospace'));
    expect(tokens.inlineCode.backgroundColor, isNull);
    expect(tokens.body.fontFamily, theme.extension<TpFontTheme>()!.uiFontFamily);
    expect(tokens.inlineCode.fontSize, tokens.body.fontSize);
    expect(tokens.inlineCode.height, tokens.body.height);
    expect(tokens.listItemGap, 8);
    expect(
      tokens.tableCellsPadding,
      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    );
    expect(tokens.h1.height, 1.3);
    expect(tokens.h1.letterSpacing, -0.02);
    expect(tokens.h2.height, 1.3);
    expect(tokens.h1TopSpacing, 40);
    expect(tokens.h2TopSpacing, 36);
    expect(tokens.h3TopSpacing, 32);
    expect(tokens.h4TopSpacing, 28);
    expect(tokens.h5TopSpacing, 28);
    expect(tokens.h6TopSpacing, 28);
    expect(tokens.headingBottom, 8);
    expect(tokens.paragraphGap, 16);
    expect(tokens.blockGap, 28);
    expect(tokens.ruleGap, 28);
    expect(tokens.listIndent, 24);
    expect(
      tokens.borderColor,
      theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
    );
    expect(
      tokens.tableHeadBackground,
      theme.colorScheme.onSurface.withValues(alpha: 0.04),
    );
    expect(tokens.link.color, theme.colorScheme.primary);
  });

  test('compact profile is tighter than document headings', () {
    final theme = themeForTest();
    final document = buildAppMarkdownTokens(theme, MarkdownProfile.document);
    final compact = buildAppMarkdownTokens(theme, MarkdownProfile.compact);

    expect(compact.h1TopSpacing, lessThan(document.h1TopSpacing));
    expect(compact.h2TopSpacing, lessThan(document.h2TopSpacing));
    expect(compact.paragraphGap, lessThan(document.paragraphGap));
    expect(compact.blockGap, lessThan(document.blockGap));
    expect(compact.h1TopSpacing, 16);
    expect(compact.h2TopSpacing, 12);
    expect(compact.paragraphGap, 12);
    expect(compact.blockGap, 12);
  });

  test('buildAppMarkdownStyleSheet bridges document tokens for file preview', () {
    final theme = themeForTest();
    final sheet = buildAppMarkdownStyleSheet(theme);
    final tokens = buildAppMarkdownTokens(theme, MarkdownProfile.document);

    expect(sheet.p, tokens.body);
    expect(sheet.blockSpacing, tokens.blockGap);
    expect(sheet.h1Padding, EdgeInsets.only(top: tokens.h1TopSpacing));
  });
}
