import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('autoUiZoomForDevicePixelRatio = 1/dpr (desktop baseline)', () {
    expect(
      autoUiZoomForDevicePixelRatio(1.0, useMacOSBaselines: false),
      1.0,
    ); // Linux @100%
    expect(
      autoUiZoomForDevicePixelRatio(1.5, useMacOSBaselines: false),
      closeTo(0.667, 0.001),
    ); // Win @150%
    expect(autoUiZoomForDevicePixelRatio(1.25, useMacOSBaselines: false), 0.8);
    expect(autoUiZoomForDevicePixelRatio(2.0, useMacOSBaselines: false), 0.5);
    expect(autoUiZoomForDevicePixelRatio(0.0, useMacOSBaselines: false), 1.0);
  });

  test('autoUiZoomForDevicePixelRatio uses macOS standard baseline', () {
    expect(kMacUiZoomBaseline, 1.26);
    expect(
      autoUiZoomForDevicePixelRatio(2.0, useMacOSBaselines: true),
      closeTo(1.26 / 2.0, 0.0001),
    );
    expect(
      autoUiZoomForDevicePixelRatio(1.0, useMacOSBaselines: true),
      kMacUiZoomBaseline,
    );
  });

  test(
    'autoUiZoomForDevicePixelRatio uses mobile standard baseline',
    () {
      // Product lock: denser than desktop 1.0 so more chrome fits on phone.
      expect(kMobileUiZoomBaseline, 0.7);
      expect(
        autoUiZoomForDevicePixelRatio(
          3.0,
          compensateDisplayScaling: false,
        ),
        kMobileUiZoomBaseline,
      );
      expect(
        autoUiZoomForDevicePixelRatio(
          2.0,
          compensateDisplayScaling: false,
        ),
        kMobileUiZoomBaseline,
      );
      expect(
        resolveRelativeScale(
          scaleId: 'standard',
          customMultiplier: 1.0,
          baseline: kMobileUiZoomBaseline,
        ),
        kMobileUiZoomBaseline,
      );
    },
  );

  test(
    'autoTextScaleForSystem = osTextScale × dpr (desktop text baseline)',
    () {
      expect(
        autoTextScaleForSystem(1.5, 1.0, useMacOSBaselines: false),
        1.5,
      ); // Ubuntu GNOME 1.5 @100%
      expect(
        autoTextScaleForSystem(1.0, 1.5, useMacOSBaselines: false),
        1.5,
      ); // Windows @150%
      expect(autoTextScaleForSystem(1.0, 1.0, useMacOSBaselines: false), 1.0);
      expect(
        autoTextScaleForSystem(1.5, 2.0, useMacOSBaselines: false),
        kTypographyCustomMultiplierMax,
      ); // clamped
      expect(autoTextScaleForSystem(0.0, 0.0, useMacOSBaselines: false), 1.0);
    },
  );

  test('autoTextScaleForSystem uses macOS standard baseline', () {
    expect(kMacTextScaleBaseline, 0.72);
    expect(
      autoTextScaleForSystem(1.0, 2.0, useMacOSBaselines: true),
      closeTo(2.0 * kMacTextScaleBaseline, 0.0001),
    );
    expect(
      autoTextScaleForSystem(1.0, 1.0, useMacOSBaselines: true),
      kMacTextScaleBaseline,
    );
    expect(
      resolveRelativeScale(
        scaleId: 'standard',
        customMultiplier: 1.0,
        baseline: 2.0 * kMacTextScaleBaseline,
      ),
      closeTo(2.0 * kMacTextScaleBaseline, 0.0001),
    );
  });

  test(
    'autoTextScaleForSystem uses mobile baseline when not compensating',
    () {
      // Product lock: larger than desktop 1.0 for touch readability.
      expect(kMobileTextScaleBaseline, 1.3);
      expect(
        autoTextScaleForSystem(
          1.0,
          3.0,
          compensateDisplayScaling: false,
        ),
        closeTo(kMobileTextScaleBaseline, 0.0001),
      );
      expect(
        autoTextScaleForSystem(
          1.2,
          3.0,
          compensateDisplayScaling: false,
        ),
        closeTo(1.2 * kMobileTextScaleBaseline, 0.0001),
      );
    },
  );

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
