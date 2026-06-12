import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('AppIconSizeTheme scales roles by the multiplier', () {
    final comfy = AppIconSizeTheme.fromScale(AppTypographyScale.comfortable);
    expect(comfy.md, AppIconSizes.mdBase * AppTypographyScale.comfortable.multiplier);
    expect(comfy.list, AppIconSizes.listBase * AppTypographyScale.comfortable.multiplier);
  });

  test('default IconThemeData size scales with the active scale', () {
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    expect(std.iconTheme.size, AppIconSizes.mdBase);
    expect(comfy.iconTheme.size, greaterThan(std.iconTheme.size!));
    expect(comfy.extension<AppIconSizeTheme>(), isNotNull);
  });
}
