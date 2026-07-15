import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('fromScale uses medium baselines at multiplier 1', () {
    final c = TpControlMetrics.fromScale(AppTypographyScale.standard.multiplier);
    expect(c.height, TpControlMetrics.heightBase);
    expect(c.minWidth, TpControlMetrics.minWidthBase);
    expect(c.horizontalPadding, TpControlMetrics.horizontalPaddingBase);
    expect(c.verticalPadding, TpControlMetrics.verticalPaddingBase);
    expect(c.radius, TpControlMetrics.radiusBase);
    expect(c.input.height, TpControlMetrics.inputHeightBase);
    expect(
      c.input.horizontalPadding,
      TpControlMetrics.inputHorizontalPaddingBase,
    );
    expect(c.input.verticalPadding, TpControlMetrics.inputVerticalPaddingBase);
    expect(c.small.height, TpControlMetrics.smallBase.height);
    expect(c.large.height, TpControlMetrics.largeBase.height);
  });

  test('fromScale multiplies tokens by typography multiplier', () {
    final c = TpControlMetrics.fromScale(
      AppTypographyScale.comfortable.multiplier,
    );
    final m = AppTypographyScale.comfortable.multiplier;
    expect(c.height, TpControlMetrics.heightBase * m);
    expect(c.input.height, TpControlMetrics.inputHeightBase * m);
    expect(c.radius, TpControlMetrics.radiusBase * m);
    expect(c.small.height, TpControlMetrics.smallBase.height * m);
    expect(c.large.height, TpControlMetrics.largeBase.height * m);
  });

  test('metricsFor returns size presets', () {
    final c = TpControlMetrics.fromScale(AppTypographyScale.standard.multiplier);
    expect(c.metricsFor(TpControlSize.small).height, c.small.height);
    expect(c.metricsFor(TpControlSize.medium).height, c.medium.height);
    expect(c.metricsFor(TpControlSize.large).height, c.large.height);
    expect(c.small.height, lessThan(c.medium.height));
    expect(c.medium.height, lessThan(c.large.height));
  });
}
