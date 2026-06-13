import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('AppIconSizeTheme.resolved uses baseline sizes at multiplier 1.0', () {
    final resolved = AppIconSizeTheme.resolved();
    expect(resolved.md, AppIconSizes.mdBase);
    expect(resolved.list, AppIconSizes.listBase);
  });

  test('resolveIconMultiplier ignores OS text baseline', () {
    const osBaseline = 1.5;
    final mapped = AppIconSizes.resolveIconMultiplier(
      effectiveTextMultiplier: osBaseline,
      textBaseline: osBaseline,
    );
    expect(mapped, AppIconSizes.baselineScale);
    expect(mapped, lessThan(osBaseline));
  });

  test('resolveIconMultiplier dampens user preset delta', () {
    const baseline = 1.0;
    final comfy = AppTypographyScale.comfortable.multiplier;
    final mapped = AppIconSizes.resolveIconMultiplier(
      effectiveTextMultiplier: comfy,
      textBaseline: baseline,
    );
    final linearMapped = AppIconSizes.baselineScale * comfy;
    expect(
      mapped,
      closeTo(
        AppIconSizes.baselineScale *
            (1.0 +
                (comfy - 1.0) * AppIconSizes.userScaleTracking),
        0.001,
      ),
    );
    expect(mapped, lessThan(linearMapped));
  });

  test('icon sizes scale with mapped icon multiplier in theme', () {
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);

    final stdIconMult = AppIconSizes.resolveIconMultiplier(
      effectiveTextMultiplier: 1.0,
      textBaseline: 1.0,
    );
    expect(std.iconTheme.size, AppIconSizes.mdBase * stdIconMult);
    expect(
      comfy.iconTheme.size,
      greaterThan(std.iconTheme.size!),
    );
    expect(
      comfy.extension<AppIconSizeTheme>()!.md,
      greaterThan(std.extension<AppIconSizeTheme>()!.md),
    );
  });
}
