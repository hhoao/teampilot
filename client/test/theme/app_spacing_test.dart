import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('fromScale multiplies base tokens by the scale multiplier', () {
    final compact = TpSpacing.fromScale(AppTypographyScale.compact.multiplier);
    expect(compact.scale, AppTypographyScale.compact.multiplier);
    expect(
      compact.md,
      TpSpacing.mdBase * AppTypographyScale.compact.multiplier,
    );
    expect(
      compact.lg,
      TpSpacing.lgBase * AppTypographyScale.compact.multiplier,
    );
  });

  test('standard scale leaves tokens at baseline', () {
    final std = TpSpacing.fromScale(1.0);
    expect(std.scale, 1.0);
    expect(std.md, TpSpacing.mdBase);
    expect(std.xxl, TpSpacing.xxlBase);
  });
}
