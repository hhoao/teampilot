import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_font_resolver.dart';
import 'package:teampilot/theme/app_fonts.dart';
import 'package:teampilot/theme/app_markdown_style_sheet.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

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
    final mono = theme.extension<AppFontTheme>()!;

    expect(sheet.code?.fontFamily, mono.monoFontFamily);
    expect(sheet.code?.fontFamilyFallback, mono.monoFontFamilyFallback);
    expect(sheet.code?.fontFamily, isNot('monospace'));
    expect(sheet.p?.fontFamily, fonts.uiFamily);
    expect(sheet.code?.fontSize, sheet.p?.fontSize);
    expect(sheet.code?.height, sheet.p?.height);
  });
}
