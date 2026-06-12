import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_spacing.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('fromScale multiplies base tokens by the scale multiplier', () {
    final compact = AppSpacingTheme.fromScale(AppTypographyScale.compact);
    expect(compact.scale, AppTypographyScale.compact.multiplier);
    expect(compact.md, AppSpacingTheme.mdBase * AppTypographyScale.compact.multiplier);
    expect(compact.lg, AppSpacingTheme.lgBase * AppTypographyScale.compact.multiplier);
  });

  test('standard scale leaves tokens at baseline', () {
    final std = AppSpacingTheme.fromScale(AppTypographyScale.standard);
    expect(std.scale, 1.0);
    expect(std.md, AppSpacingTheme.mdBase);
    expect(std.xxl, AppSpacingTheme.xxlBase);
  });

  test('lerp switches over at the halfway point', () {
    final a = AppSpacingTheme.fromScale(AppTypographyScale.compact);
    final b = AppSpacingTheme.fromScale(AppTypographyScale.comfortable);
    expect(a.lerp(b, 0.6), b);
    expect(a.lerp(b, 0.4), a);
  });
}
