import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('autoUiZoomForDevicePixelRatio = 1/dpr (standard zoom baseline)', () {
    expect(autoUiZoomForDevicePixelRatio(1.0), 1.0); // Linux/macOS @100%
    expect(autoUiZoomForDevicePixelRatio(1.5), closeTo(0.667, 0.001)); // Win @150%
    expect(autoUiZoomForDevicePixelRatio(1.25), 0.8);
    expect(autoUiZoomForDevicePixelRatio(2.0), 0.5);
    expect(autoUiZoomForDevicePixelRatio(0.0), 1.0); // guard against /0
  });

  test('autoTextScaleForSystem = osTextScale × dpr (standard text baseline)', () {
    expect(autoTextScaleForSystem(1.5, 1.0), 1.5); // Ubuntu GNOME 1.5 @100%
    expect(autoTextScaleForSystem(1.0, 1.5), 1.5); // Windows @150%
    expect(autoTextScaleForSystem(1.0, 1.0), 1.0);
    expect(autoTextScaleForSystem(1.5, 2.0), kTypographyCustomMultiplierMax); // clamped
    expect(autoTextScaleForSystem(0.0, 0.0), 1.0); // guards
  });

  test('resolveRelativeScale = baseline × preset multiplier', () {
    // standard == the baseline itself
    expect(
      resolveRelativeScale(
        scaleId: 'standard',
        customMultiplier: 1.0,
        baseline: 0.8,
      ),
      0.8,
    );
    // compact is a bit tighter than standard
    expect(
      resolveRelativeScale(
        scaleId: 'compact',
        customMultiplier: 1.0,
        baseline: 1.0,
      ),
      AppTypographyScale.compact.multiplier,
    );
    // custom is a fraction of standard
    expect(
      resolveRelativeScale(
        scaleId: 'custom',
        customMultiplier: 1.2,
        baseline: 1.0,
      ),
      closeTo(1.2, 0.0001),
    );
  });
}
