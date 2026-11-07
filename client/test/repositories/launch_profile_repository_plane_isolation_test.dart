import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../support/in_memory_filesystem.dart';

RuntimeContext _context(InMemoryFilesystem fs, {required String appDataRoot}) =>
    RuntimeContext(
      target: RuntimeTarget.local(),
      filesystem: fs,
      home: '/home/test',
      cwd: '/home/test',
      appDataRoot: appDataRoot,
      paths: AppPaths(appDataRoot),
    );

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

  group('home swap', () {
    test('the previous plane profiles are not served after a swap', () async {
      final fsA = InMemoryFilesystem();
      final fsB = InMemoryFilesystem();
      final storage = HomeStorage(_context(fsA, appDataRoot: '/plane-a'));
      final repo = LaunchProfileRepository(storage: storage);

      await repo.save(const TeamProfile(id: 'alpha', name: 'Alpha'));
      expect((await repo.loadAll()).map((p) => p.id), ['alpha']);

      await storage.swap(_context(fsB, appDataRoot: '/plane-b'));

      expect(await repo.loadAll(), isEmpty);
    });

    test('swapping back reloads the original plane instead of its old '
        'snapshot', () async {
      final fsA = InMemoryFilesystem();
      final fsB = InMemoryFilesystem();
      final contextA = _context(fsA, appDataRoot: '/plane-a');
      final storage = HomeStorage(contextA);
      final repo = LaunchProfileRepository(storage: storage);

      await repo.save(const TeamProfile(id: 'alpha', name: 'Alpha'));
      expect((await repo.loadAll()).map((p) => p.id), ['alpha']);

      await storage.swap(_context(fsB, appDataRoot: '/plane-b'));
      expect(await repo.loadAll(), isEmpty);
      await repo.save(const TeamProfile(id: 'beta', name: 'Beta'));
      expect((await repo.loadAll()).map((p) => p.id), ['beta']);

      await storage.swap(contextA);

      expect((await repo.loadAll()).map((p) => p.id), ['alpha']);
    });
  });
}
