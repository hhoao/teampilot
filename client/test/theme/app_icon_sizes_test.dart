import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('AppIconSizeTheme.resolved uses the resolved (base × multiplier) sizes', () {
    final resolved = AppIconSizeTheme.resolved();
    expect(resolved.md, AppIconSizes.md);
    expect(resolved.list, AppIconSizes.list);
  });

  test('icon sizes are fixed (independent of the text-size scale)', () {
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);

    // Icons follow the icon multiplier, not the text-size scale.
    expect(std.iconTheme.size, AppIconSizes.md);
    expect(comfy.iconTheme.size, AppIconSizes.md);
    expect(comfy.extension<AppIconSizeTheme>(), isNotNull);
  });
}
