import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/extension/extension_probe.dart';

void main() {
  group('ExtensionProbe.isReady', () {
    test('true when found, version OK, and no missing requirements', () {
      const probe = ExtensionProbe(
        found: true,
        version: '0.24.1',
        satisfiesMinVersion: true,
        missingRequirements: [],
      );
      expect(probe.isReady, isTrue);
    });

    test('false when a requirement is missing', () {
      const probe = ExtensionProbe(found: true, missingRequirements: ['jq']);
      expect(probe.isReady, isFalse);
    });

    test('false when version too old', () {
      const probe = ExtensionProbe(found: true, satisfiesMinVersion: false);
      expect(probe.isReady, isFalse);
    });

    test('false when not found', () {
      const probe = ExtensionProbe(found: false);
      expect(probe.isReady, isFalse);
    });
  });
}
