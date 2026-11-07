import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  test('same root string on another plane does not leak launch profiles',
      () async {
    final fsA = InMemoryFilesystem();
    final fsB = InMemoryFilesystem();
    const root = '/home/ubuntu/.teampilot/launch-profiles';

    final repoA = LaunchProfileRepository(
      rootDir: root,
      storage: fakeHomeStorage(
        filesystem: fsA,
        appDataRoot: '/home/ubuntu/.teampilot',
      ),
    );
    final repoB = LaunchProfileRepository(
      rootDir: root,
      storage: fakeHomeStorage(
        filesystem: fsB,
        appDataRoot: '/home/ubuntu/.teampilot',
      ),
    );

    await repoA.save(const TeamProfile(id: 'alpha', name: 'Alpha'));
    expect((await repoA.loadAll()).map((p) => p.id), ['alpha']);

    expect(await repoB.loadAll(), isEmpty);
  });
}
