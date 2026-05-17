import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/connection_mode.dart';
import 'package:teampilot/services/connection_mode_service.dart';

void main() {
  test('requiresSshProfileSetup only in ssh mode without profiles', () {
    final service = ConnectionModeService(
      readPreferredMode: () => ConnectionMode.ssh,
      hasSshProfiles: () => false,
    );

    expect(service.isSshMode, isTrue);
    expect(service.requiresSshProfileSetup, isTrue);
  });

  test('local mode never requires ssh profile setup', () {
    final service = ConnectionModeService(
      readPreferredMode: () => ConnectionMode.localPty,
      hasSshProfiles: () => false,
    );

    expect(service.isLocalMode, isTrue);
    expect(service.requiresSshProfileSetup, isFalse);
  });
}
