import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('autoUiZoomForDevicePixelRatio compensates for display scaling', () {
    expect(autoUiZoomForDevicePixelRatio(1.0), 1.0); // Linux/macOS @100%
    expect(autoUiZoomForDevicePixelRatio(1.5), closeTo(0.667, 0.001)); // Win @150%
    expect(autoUiZoomForDevicePixelRatio(1.25), 0.8);
    expect(autoUiZoomForDevicePixelRatio(2.0), kUiZoomMin); // clamped
    expect(autoUiZoomForDevicePixelRatio(0.0), 1.0); // guard against /0
  });

  test('normalizeUiZoom keeps 0 as auto and clamps explicit values', () {
    expect(normalizeUiZoom(0), 0.0);
    expect(normalizeUiZoom(-1), 0.0);
    expect(normalizeUiZoom(0.92), 0.92);
    expect(normalizeUiZoom(3.0), kUiZoomMax);
    expect(normalizeUiZoom(0.1), kUiZoomMin);
  });
}
