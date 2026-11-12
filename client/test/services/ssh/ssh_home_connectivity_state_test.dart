import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ssh/ssh_home_connectivity_state.dart';

void main() {
  group('SshHomeConnectivityState', () {
    test('up() clears every failure surface in one value (invariant 3)', () {
      final dirty = const SshHomeConnectivityState(
        profileId: 'p1',
        phase: SshPhase.reconnecting,
        failure: SshFailureKind.authFailed,
        errorDetail: 'bad password',
        attempt: 4,
        storageLive: false,
      );
      final up = SshHomeConnectivityState.up('p1');

      expect(up.phase, SshPhase.up);
      expect(up.storageLive, isTrue);
      expect(up.failure, isNull);
      expect(up.errorDetail, isNull);
      expect(up.attempt, 0);
      expect(up.planeRebinding, isFalse);
      // The constructor, not callers, owns the invariant.
      expect(dirty.failure, SshFailureKind.authFailed);
    });

    test('copyWith preserves unrelated fields and value equality holds', () {
      const a = SshHomeConnectivityState(profileId: 'p1');
      final b = a.copyWith(phase: SshPhase.connecting, attempt: 1);
      expect(b.profileId, 'p1');
      expect(b.phase, SshPhase.connecting);
      expect(b.attempt, 1);
      expect(b.storageLive, isFalse);
      expect(a == const SshHomeConnectivityState(profileId: 'p1'), isTrue);
      expect(a == b, isFalse);
    });

    test('isUp / isDown / retryActive agree with the phase table', () {
      expect(SshHomeConnectivityState.up('p1').isUp, isTrue);
      for (final phase in [
        SshPhase.unreachable,
        SshPhase.suspended,
        SshPhase.failed,
      ]) {
        expect(
          SshHomeConnectivityState(profileId: 'p1', phase: phase).isDown,
          isTrue,
          reason: '$phase must be down',
        );
      }
      expect(
        const SshHomeConnectivityState(
          profileId: 'p1',
          phase: SshPhase.reconnecting,
        ).retryActive,
        isTrue,
      );
    });
  });
}
