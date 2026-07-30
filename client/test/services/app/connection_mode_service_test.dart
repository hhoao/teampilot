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

  test('hasBoundAndroidWorkHome true for termux, false for local', () {
    final termux = ConnectionModeService(
      defaultTargetResolver: RuntimeTarget.termux,
      hasSshProfiles: () => false,
    );
    final localWithProfiles = ConnectionModeService(
      defaultTargetResolver: RuntimeTarget.local,
      hasSshProfiles: () => true,
    );

    expect(termux.hasBoundAndroidWorkHome, isTrue);
    expect(localWithProfiles.hasBoundAndroidWorkHome, isFalse);
  });

  test('requiresSshProfileSetup false for termux home with no profiles', () {
    final service = ConnectionModeService(
      defaultTargetResolver: RuntimeTarget.termux,
      hasSshProfiles: () => false,
    );

    expect(service.requiresSshProfileSetup, isFalse);
  });

  test('isTermuxMode true and isSshMode false for termux', () {
    final service = ConnectionModeService(
      defaultTargetResolver: RuntimeTarget.termux,
      hasSshProfiles: () => false,
    );

    expect(service.isTermuxMode, isTrue);
    expect(service.isSshMode, isFalse);
  });

  test('isRemoteWorkPlane true for termux and ssh', () {
    final termux = ConnectionModeService(
      defaultTargetResolver: RuntimeTarget.termux,
      hasSshProfiles: () => false,
    );
    final ssh = ConnectionModeService(
      defaultTargetResolver: () => RuntimeTarget.ssh('p1', label: 'box'),
      hasSshProfiles: () => true,
    );

    expect(termux.isRemoteWorkPlane, isTrue);
    expect(ssh.isRemoteWorkPlane, isTrue);
  });

  test('termux is not local mode', () {
    final service = ConnectionModeService(
      defaultTargetResolver: RuntimeTarget.termux,
      hasSshProfiles: () => false,
    );

    expect(service.isLocalMode, isFalse);
  });
}
