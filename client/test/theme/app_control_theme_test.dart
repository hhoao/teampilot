import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_control_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('fromScale uses medium baselines at multiplier 1', () {
    final c = AppControlTheme.fromScale(AppTypographyScale.standard);
    expect(c.height, AppControlTheme.heightBase);
    expect(c.minWidth, AppControlTheme.minWidthBase);
    expect(c.horizontalPadding, AppControlTheme.horizontalPaddingBase);
    expect(c.verticalPadding, AppControlTheme.verticalPaddingBase);
    expect(c.radius, AppControlTheme.radiusBase);
    expect(c.input.height, AppControlTheme.inputHeightBase);
    expect(
      c.input.horizontalPadding,
      AppControlTheme.inputHorizontalPaddingBase,
    );
    expect(c.input.verticalPadding, AppControlTheme.inputVerticalPaddingBase);
    expect(c.small.height, AppControlTheme.smallBase.height);
    expect(c.large.height, AppControlTheme.largeBase.height);
  });

  test('fromScale multiplies tokens by typography multiplier', () {
    final c = AppControlTheme.fromScale(AppTypographyScale.comfortable);
    final m = AppTypographyScale.comfortable.multiplier;
    expect(c.height, AppControlTheme.heightBase * m);
    expect(c.input.height, AppControlTheme.inputHeightBase * m);
    expect(c.radius, AppControlTheme.radiusBase * m);
    expect(c.small.height, AppControlTheme.smallBase.height * m);
    expect(c.large.height, AppControlTheme.largeBase.height * m);
  });

  test('metricsFor returns size presets', () {
    final c = AppControlTheme.fromScale(AppTypographyScale.standard);
    expect(c.metricsFor(AppControlSize.small).height, c.small.height);
    expect(c.metricsFor(AppControlSize.medium).height, c.medium.height);
    expect(c.metricsFor(AppControlSize.large).height, c.large.height);
    expect(c.small.height, lessThan(c.medium.height));
    expect(c.medium.height, lessThan(c.large.height));
  });
}
