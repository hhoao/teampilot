import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/antigravity/capabilities/executable.dart';

void main() {
  test('executable defaults to agy and supports local install', () {
    const cap = AntigravityExecutableCapability();
    expect(cap.defaultExecutableName, 'agy');
    expect(cap.preferencesPathKey, 'cli.antigravity.path');
    expect(cap.supportsInstaller, isTrue);
  });
}
