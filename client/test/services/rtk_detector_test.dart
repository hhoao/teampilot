import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/rtk_detector.dart';

void main() {
  group('RtkDetector', () {
    const detector = RtkDetector();

    test('isVersionSupported requires >= 0.23.0', () {
      expect(detector.isVersionSupported('0.41.0'), isTrue);
      expect(detector.isVersionSupported('0.22.9'), isFalse);
      expect(detector.isVersionSupported('1.0.0'), isTrue);
      expect(detector.isVersionSupported('rtk 0.30.1 extra'), isTrue);
    });
  });
}
