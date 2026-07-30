import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/storage/home_ssh_profile_impact.dart';

void main() {
  const home = SshProfile(
    id: 'p1',
    name: 'Home',
    host: 'home.example.com',
    username: 'alice',
  );
  const other = SshProfile(
    id: 'p2',
    name: 'Other',
    host: 'other.example.com',
    username: 'bob',
  );

  test('local home ignores ssh catalog churn', () {
    expect(
      resolveHomeSshProfileImpact(
        homeTargetId: 'local',
        previous: const [],
        next: [home, other],
      ),
      HomeSshProfileImpact.none,
    );
  });

  test('initial hydration of home profile is none', () {
    expect(
      resolveHomeSshProfileImpact(
        homeTargetId: 'ssh:p1',
        previous: const [],
        next: [home],
      ),
      HomeSshProfileImpact.none,
    );
  });

  test('adding unrelated profile is none', () {
    expect(
      resolveHomeSshProfileImpact(
        homeTargetId: 'ssh:p1',
        previous: const [home],
        next: [home, other],
      ),
      HomeSshProfileImpact.none,
    );
  });

  test('renaming home profile is none', () {
    expect(
      resolveHomeSshProfileImpact(
        homeTargetId: 'ssh:p1',
        previous: const [home],
        next: [home.copyWith(name: 'Renamed')],
      ),
      HomeSshProfileImpact.none,
    );
  });

  test('editing unrelated profile is none', () {
    expect(
      resolveHomeSshProfileImpact(
        homeTargetId: 'ssh:p1',
        previous: [home, other],
        next: [home, other.copyWith(host: 'changed.example.com')],
      ),
      HomeSshProfileImpact.none,
    );
  });

  test('home connection fingerprint change requires reinstall', () {
    expect(
      resolveHomeSshProfileImpact(
        homeTargetId: 'ssh:p1',
        previous: const [home],
        next: [home.copyWith(host: 'new.example.com')],
      ),
      HomeSshProfileImpact.homeConnectionChanged,
    );
  });

  test('deleting home profile requires fallback', () {
    expect(
      resolveHomeSshProfileImpact(
        homeTargetId: 'ssh:p1',
        previous: [home, other],
        next: const [other],
      ),
      HomeSshProfileImpact.homeProfileMissing,
    );
  });

  test('deleting unrelated profile is none', () {
    expect(
      resolveHomeSshProfileImpact(
        homeTargetId: 'ssh:p1',
        previous: [home, other],
        next: const [home],
      ),
      HomeSshProfileImpact.none,
    );
  });
}
