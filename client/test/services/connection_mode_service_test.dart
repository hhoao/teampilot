import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/connection_mode.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';

void main() {
  test('isSshMode derives from default target kind', () {
    var target = RuntimeTarget.local();
    final svc = ConnectionModeService(
      defaultTargetResolver: () => target,
      hasSshProfiles: () => true,
    );
    expect(svc.isSshMode, isFalse);
    expect(svc.effectiveMode, ConnectionMode.localPty);

    target = RuntimeTarget.ssh('p1', label: 'box');
    expect(svc.isSshMode, isTrue);
    expect(svc.effectiveMode, ConnectionMode.ssh);
  });

  test('requiresSshProfileSetup when ssh and no profiles', () {
    final svc = ConnectionModeService(
      defaultTargetResolver: () => RuntimeTarget.ssh('p1', label: 'box'),
      hasSshProfiles: () => false,
    );
    expect(svc.requiresSshProfileSetup, isTrue);
  });

  test('local target never requires ssh setup', () {
    final svc = ConnectionModeService(
      defaultTargetResolver: RuntimeTarget.local,
      hasSshProfiles: () => false,
    );
    expect(svc.requiresSshProfileSetup, isFalse);
    expect(svc.isLocalMode, isTrue);
  });
}
