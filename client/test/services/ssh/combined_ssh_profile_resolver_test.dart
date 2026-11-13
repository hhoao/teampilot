import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/ssh/combined_ssh_profile_resolver.dart';

const _workload = SshProfile(
  id: 'workload',
  name: 'Workload',
  host: 'work.example.com',
  username: 'bob',
);

const _home = SshProfile(
  id: 'home',
  name: 'Home',
  host: 'home.example.com',
  username: 'alice',
);

SshProfile? Function(String id) _resolverFrom(Map<String, SshProfile> byId) =>
    (id) => byId[id];

void main() {
  group('combinedSshProfileResolver', () {
    test('resolves a B-only workload id from the B source', () {
      final resolve = combinedSshProfileResolver(
        workloadById: _resolverFrom({'workload': _workload}),
        homeById: _resolverFrom({}),
      );

      expect(resolve('workload'), _workload);
    });

    test('falls back to the A-source home profile when B misses', () {
      final resolve = combinedSshProfileResolver(
        workloadById: _resolverFrom({}),
        homeById: _resolverFrom({'home': _home}),
      );

      expect(resolve('home'), _home);
    });

    test('B source takes precedence when both sources contain the id', () {
      final resolve = combinedSshProfileResolver(
        workloadById: _resolverFrom({'home': _workload}),
        homeById: _resolverFrom({'home': _home}),
      );

      expect(resolve('home'), _workload);
    });

    test('returns null when both sources miss (shell-factory fallback applies)',
        () {
      final resolve = combinedSshProfileResolver(
        workloadById: _resolverFrom({}),
        homeById: _resolverFrom({}),
      );

      expect(resolve('unknown'), isNull);
    });

    test('an empty B source (home plane unreachable) still resolves A', () {
      // B emits an empty list when the home plane is unreachable; the id
      // resolver must still find the device-local home profile so SSH home
      // mode and offline home binding keep working.
      final resolve = combinedSshProfileResolver(
        workloadById: _resolverFrom({}),
        homeById: _resolverFrom({'home': _home}),
      );

      expect(resolve('home'), _home);
      expect(resolve('missing'), isNull);
    });
  });
}
