import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/combined_ssh_profile_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/workspace/target_liveness.dart';

import '../support/in_memory_filesystem.dart';

/// In-memory [SshProfileRepository] with a fixed catalog, so combined-source
/// delegation can be asserted without touching the filesystem.
class _FakeRepo extends SshProfileRepository {
  _FakeRepo(this.profiles) : super(storage: fakeHomeStorage());

  final List<SshProfile> profiles;

  @override
  Future<SshProfile?> findById(String profileId) async {
    for (final p in profiles) {
      if (p.id == profileId) return p;
    }
    return null;
  }

  @override
  Future<List<SshProfile>> loadAll() async => List.of(profiles);
}

const _bShared = SshProfile(
  id: 'shared',
  name: 'workload-shared',
  host: 'b.example',
  username: 'u',
);
const _bOnly = SshProfile(
  id: 'work-only',
  name: 'workload-only',
  host: 'b.example',
  username: 'u',
);
const _aShared = SshProfile(
  id: 'shared',
  name: 'home-shared',
  host: 'a.example',
  username: 'u',
);
const _aOnly = SshProfile(
  id: 'home-only',
  name: 'home-only',
  host: 'a.example',
  username: 'u',
);

void main() {
  CombinedSshProfileRepository build() => CombinedSshProfileRepository(
    storage: fakeHomeStorage(),
    workload: _FakeRepo([_bShared, _bOnly]),
    home: _FakeRepo([_aShared, _aOnly]),
  );

  test('findById prefers the B workload catalog when both sources match',
      () async {
    final profile = await build().findById('shared');
    // Point lookup is B-first: never the A-row with the same id.
    expect(profile?.name, 'workload-shared');
    expect(profile?.host, 'b.example');
  });

  test('findById falls back to the A home-binding catalog on a B miss',
      () async {
    final profile = await build().findById('home-only');
    expect(profile?.name, 'home-only');
    expect(profile?.host, 'a.example');
  });

  test('findById returns a workload-only host (B) directly', () async {
    final profile = await build().findById('work-only');
    expect(profile?.name, 'workload-only');
  });

  test('findById returns null when neither source has the id', () async {
    expect(await build().findById('gone'), isNull);
  });

  test('loadAll is B-only so no machine list ever merges A + B', () async {
    final profiles = await build().loadAll();
    expect(profiles.map((p) => p.id), ['shared', 'work-only']);
    expect(profiles.map((p) => p.host), everyElement('b.example'));
  });

  test('mutations are rejected; writes must use the owning source repository',
      () async {
    final repo = build();
    expect(() => repo.save(_bShared), throwsUnsupportedError);
    expect(() => repo.saveAll([_bShared]), throwsUnsupportedError);
    expect(() => repo.delete('shared'), throwsUnsupportedError);
    expect(
      () => repo.saveSelectedProfileId('shared'),
      throwsUnsupportedError,
    );
  });

  test('loadSelectedProfileId is empty (no device selection on the plane)',
      () async {
    expect(await build().loadSelectedProfileId(), '');
  });

  test('a workload-only ssh:<id> folder target is alive via liveness',
      () async {
    // Integration: workspace folder liveness reads the combined repository,
    // so an `ssh:<id>` naming a B workload host is not treated as dead.
    final liveness = DefaultTargetLiveness(sshProfiles: build());
    expect(await liveness.isAlive('ssh:work-only'), isTrue);
    expect(await liveness.isAlive('ssh:home-only'), isTrue); // A fallback
    expect(await liveness.isAlive('ssh:gone'), isFalse);
  });
}
