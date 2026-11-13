import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/ssh/ssh_host_profile_assembly.dart';

const _home = SshProfile(
  id: 'home',
  name: 'Home',
  host: 'home.example.com',
  username: 'alice',
);

const _workload = SshProfile(
  id: 'workload',
  name: 'Workload',
  host: 'work.example.com',
  username: 'bob',
);

const _termuxDevice = SshProfile(
  id: 'termux',
  name: 'Termux',
  host: '127.0.0.1',
  username: 'u',
);

void main() {
  group('assembleSshHostProfiles', () {
    test('returns only the B-source workload profiles for a local home', () {
      final result = assembleSshHostProfiles(
        workloadProfiles: const [_workload],
        deviceProfiles: const [_home],
        home: RuntimeTarget.local(),
      );
      expect(result.map((p) => p.id), ['workload']);
    });

    test('appends the SSH home profile resolved from the A source', () {
      final result = assembleSshHostProfiles(
        workloadProfiles: const [_workload],
        deviceProfiles: const [_home],
        home: RuntimeTarget.ssh('home', label: 'Home'),
      );
      expect(result.map((p) => p.id), ['workload', 'home']);
    });

    test('does not duplicate the home when B source already has it', () {
      final result = assembleSshHostProfiles(
        workloadProfiles: const [_workload, _home],
        deviceProfiles: const [_home],
        home: RuntimeTarget.ssh('home', label: 'Home'),
      );
      expect(result.map((p) => p.id), ['workload', 'home']);
    });

    test('empty B source + SSH home yields the home profile only', () {
      final result = assembleSshHostProfiles(
        workloadProfiles: const [],
        deviceProfiles: const [_home],
        home: RuntimeTarget.ssh('home', label: 'Home'),
      );
      expect(result.map((p) => p.id), ['home']);
    });

    test('does not invent a home profile missing from the A source', () {
      final result = assembleSshHostProfiles(
        workloadProfiles: const [_workload],
        deviceProfiles: const [],
        home: RuntimeTarget.ssh('home', label: 'Home'),
      );
      expect(result.map((p) => p.id), ['workload']);
    });

    test('does not add a home for wsl/termux targets', () {
      // Termux carries a non-null sshProfileId and a matching A-source row,
      // but only a real SSH kind home is appended to the catalog.
      for (final home in <RuntimeTarget>[
        RuntimeTarget.wsl('Ubuntu'),
        RuntimeTarget.termux(),
      ]) {
        final result = assembleSshHostProfiles(
          workloadProfiles: const [_workload],
          deviceProfiles: const [_termuxDevice],
          home: home,
        );
        expect(result.map((p) => p.id), ['workload']);
      }
    });
  });
}
