import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/member_remote_provision_progress.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/remote/remote_preflight_cli_install.dart';

void main() {
  const base = MemberRemoteProvisionProgress(
    memberId: 'm1',
    phase: CliInstallPhase.bootstrappingNode,
    detail: 'step',
    hostLabel: 'host.example',
    error: 'oops',
  );

  test('copyWith updates phase and hostLabel', () {
    final next = base.copyWith(
      phase: CliInstallPhase.syncingRemoteWorkspace,
      hostLabel: 'other',
    );
    expect(next.memberId, 'm1');
    expect(next.phase, CliInstallPhase.syncingRemoteWorkspace);
    expect(next.detail, 'step');
    expect(next.hostLabel, 'other');
    expect(next.error, 'oops');
  });

  test('copyWith clearDetail and clearError', () {
    final cleared = base.copyWith(clearDetail: true, clearError: true);
    expect(cleared.detail, isNull);
    expect(cleared.error, isNull);
    expect(cleared.phase, CliInstallPhase.bootstrappingNode);
  });

  test('hasFailed reflects non-empty error', () {
    expect(base.hasFailed, isTrue);
    expect(base.copyWith(clearError: true).hasFailed, isFalse);
    expect(
      base.copyWith(error: '   ').hasFailed,
      isFalse,
      reason: 'whitespace-only error is not a failure',
    );
  });

  test('remoteCliInstallProgressLabel for syncingRemoteWorkspace', () {
    const progress = CliInstallProgress(
      phase: CliInstallPhase.syncingRemoteWorkspace,
    );
    expect(
      remoteCliInstallProgressLabel(progress),
      'Syncing remote workspace',
    );
  });
}
