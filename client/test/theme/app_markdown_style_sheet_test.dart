import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_font_resolver.dart';
import 'package:teampilot/theme/app_fonts.dart';
import 'package:teampilot/theme/app_markdown_style_sheet.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  test('buildAppMarkdownStyleSheet uses app mono, not monospace', () {
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

    expect(sheet.code?.fontFamily, mono.monoFontFamily);
    expect(sheet.code?.fontFamilyFallback, mono.monoFontFamilyFallback);
    expect(sheet.code?.fontFamily, isNot('monospace'));
    expect(sheet.code?.backgroundColor, isNull);
    expect(sheet.p?.fontFamily, fonts.uiFamily);
    expect(sheet.code?.fontSize, sheet.p?.fontSize);
    expect(sheet.code?.height, sheet.p?.height);
    expect(sheet.p?.height, 1.7);
    expect(sheet.blockquote?.height, 1.7);
    expect(sheet.blockSpacing, 28);
    expect(
      buildAppCompiledMarkdownStyle(theme).listItemSpacing,
      8,
    );
    expect(
      sheet.tableCellsPadding,
      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    );
    expect(sheet.h1?.height, 1.3);
    expect(sheet.h1?.letterSpacing, -0.02);
    expect(sheet.h2?.height, 1.3);
    expect(sheet.h1Padding, const EdgeInsets.only(top: 40));
    expect(sheet.h2Padding, const EdgeInsets.only(top: 36));
    expect(sheet.h3Padding, const EdgeInsets.only(top: 32));

    final compiled = buildAppCompiledMarkdownStyle(theme);
    expect(compiled.h1TopSpacing, 40);
    expect(compiled.h2TopSpacing, 36);
    expect(
      compiled.borderColor,
      theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
    );
    expect(
      compiled.tableHeadBackground,
      theme.colorScheme.onSurface.withValues(alpha: 0.04),
    );
  });
}
