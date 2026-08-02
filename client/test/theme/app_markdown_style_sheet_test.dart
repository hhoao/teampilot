import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_font_resolver.dart';
import 'package:teampilot/theme/app_fonts.dart';
import 'package:teampilot/theme/app_markdown_style_sheet.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:tp_markdown/tp_markdown.dart';

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
    final tokens = buildAppMarkdownTokens(
      theme,
      MarkdownProfile.document,
      width: TpBreakpoints.xxl,
    );
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
    expect(tokens.marginOf(MarkdownBlockKind.heading1).top, 40);
    expect(tokens.marginOf(MarkdownBlockKind.heading1).bottom, 8);
    expect(tokens.marginOf(MarkdownBlockKind.heading2).top, 36);
    expect(tokens.marginOf(MarkdownBlockKind.heading2).bottom, 8);
    expect(tokens.marginOf(MarkdownBlockKind.heading3).top, 32);
    expect(tokens.marginOf(MarkdownBlockKind.heading3).bottom, 8);
    expect(tokens.marginOf(MarkdownBlockKind.heading4).top, 28);
    expect(tokens.marginOf(MarkdownBlockKind.heading4).bottom, 8);
    expect(tokens.marginOf(MarkdownBlockKind.heading5).top, 28);
    expect(tokens.marginOf(MarkdownBlockKind.heading5).bottom, 8);
    expect(tokens.marginOf(MarkdownBlockKind.heading6).top, 28);
    expect(tokens.marginOf(MarkdownBlockKind.heading6).bottom, 8);
    expect(tokens.marginOf(MarkdownBlockKind.paragraph).bottom, 16);
    expect(tokens.marginOf(MarkdownBlockKind.code).bottom, 28);
    expect(tokens.marginOf(MarkdownBlockKind.list).bottom, 28);
    expect(tokens.marginOf(MarkdownBlockKind.blockquote).bottom, 28);
    expect(tokens.marginOf(MarkdownBlockKind.table).bottom, 28);
    expect(tokens.marginOf(MarkdownBlockKind.horizontalRule).bottom, 28);
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
    final styles = TpTextStyles(theme);
    expect(tokens.strongWeight, styles.mdBold.fontWeight);
    expect(tokens.emphasisFontStyle, FontStyle.italic);
    expect(tokens.strikeDecoration, TextDecoration.lineThrough);
  });

  test('compact profile is tighter than document headings', () {
    final theme = themeForTest();
    final document = buildAppMarkdownTokens(
      theme,
      MarkdownProfile.document,
      width: TpBreakpoints.xxl,
    );
    final compact = buildAppMarkdownTokens(
      theme,
      MarkdownProfile.compact,
      width: TpBreakpoints.xxl,
    );

    expect(
      compact.marginOf(MarkdownBlockKind.heading1).top,
      lessThan(document.marginOf(MarkdownBlockKind.heading1).top),
    );
    expect(
      compact.marginOf(MarkdownBlockKind.heading2).top,
      lessThan(document.marginOf(MarkdownBlockKind.heading2).top),
    );
    expect(
      compact.marginOf(MarkdownBlockKind.paragraph).bottom,
      lessThan(document.marginOf(MarkdownBlockKind.paragraph).bottom),
    );
    expect(
      compact.marginOf(MarkdownBlockKind.code).bottom,
      lessThan(document.marginOf(MarkdownBlockKind.code).bottom),
    );
    expect(compact.marginOf(MarkdownBlockKind.heading1).top, 16);
    expect(compact.marginOf(MarkdownBlockKind.heading2).top, 12);
    expect(compact.marginOf(MarkdownBlockKind.paragraph).bottom, 12);
    expect(compact.marginOf(MarkdownBlockKind.code).bottom, 12);
  });

  test('document margins scale with width between sm and xxl', () {
    final theme = themeForTest();
    final sm = buildAppMarkdownTokens(
      theme,
      MarkdownProfile.document,
      width: TpBreakpoints.sm,
    );
    final xxl = buildAppMarkdownTokens(
      theme,
      MarkdownProfile.document,
      width: TpBreakpoints.xxl,
    );

    expect(
      sm.marginOf(MarkdownBlockKind.heading1).top,
      lessThan(xxl.marginOf(MarkdownBlockKind.heading1).top),
    );
    expect(
      sm.marginOf(MarkdownBlockKind.paragraph).bottom,
      lessThan(xxl.marginOf(MarkdownBlockKind.paragraph).bottom),
    );
  });
}
