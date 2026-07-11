import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_control_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('fromScale uses baseline 40 at multiplier 1', () {
    final c = AppControlTheme.fromScale(AppTypographyScale.standard);
    expect(c.height, 40);
    expect(c.minWidth, 64);
    expect(c.horizontalPadding, 12);
    expect(c.verticalPadding, 13);
  });

  test('fromScale multiplies tokens by typography multiplier', () {
    final c = AppControlTheme.fromScale(AppTypographyScale.comfortable);
    expect(c.height, 40 * AppTypographyScale.comfortable.multiplier);
    expect(c.minWidth, 64 * AppTypographyScale.comfortable.multiplier);
    expect(c.horizontalPadding, 12 * AppTypographyScale.comfortable.multiplier);
    expect(c.verticalPadding, 13 * AppTypographyScale.comfortable.multiplier);
  });
}
