import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('TpIconSizes.fromScale uses baseline sizes at multiplier 1.0', () {
    final resolved = TpIconSizes.fromScale(1.0);
    expect(resolved.md, TpIconSizes.mdBase);
    expect(resolved.hero, TpIconSizes.heroBase);
  });

  test('resolveIconMultiplier ignores OS text baseline', () {
    const osBaseline = 1.5;
    final mapped = TpIconSizes.resolveIconMultiplier(
      effectiveTextMultiplier: osBaseline,
      textBaseline: osBaseline,
    );
    expect(mapped, TpIconSizes.baselineScale);
    expect(mapped, lessThan(osBaseline));
  });

  test('resolveIconMultiplier dampens user preset delta', () {
    const baseline = 1.0;
    final comfy = AppTypographyScale.comfortable.multiplier;
    final mapped = TpIconSizes.resolveIconMultiplier(
      effectiveTextMultiplier: comfy,
      textBaseline: baseline,
    );
    final linearMapped = TpIconSizes.baselineScale * comfy;
    expect(
      mapped,
      closeTo(
        TpIconSizes.baselineScale *
            (1.0 + (comfy - 1.0) * TpIconSizes.userScaleTracking),
        0.001,
      ),
    );
    expect(mapped, lessThan(linearMapped));
  });

  test('icon sizes scale with mapped icon multiplier in theme', () {
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);

    final stdIconMult = TpIconSizes.resolveIconMultiplier(
      effectiveTextMultiplier: 1.0,
      textBaseline: 1.0,
    );
    expect(std.iconTheme.size, TpIconSizes.mdBase * stdIconMult);
    expect(comfy.iconTheme.size, greaterThan(std.iconTheme.size!));
  });
}
