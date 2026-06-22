import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';

void main() {
  test('requiresSshProfileSetup only in ssh mode without profiles', () {
    final service = ConnectionModeService(
      defaultTargetResolver: () => RuntimeTarget.ssh('p1', label: 'box'),
      hasSshProfiles: () => false,
    );

    expect(service.isSshMode, isTrue);
    expect(service.requiresSshProfileSetup, isTrue);
  });

  test('local mode never requires ssh profile setup', () {
    final service = ConnectionModeService(
      defaultTargetResolver: RuntimeTarget.local,
      hasSshProfiles: () => false,
    );

    expect(service.isLocalMode, isTrue);
    expect(service.requiresSshProfileSetup, isFalse);
  });
}
