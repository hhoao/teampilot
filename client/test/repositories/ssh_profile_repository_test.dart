import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import '../support/test_runtime_context.dart';
import '../support/in_memory_filesystem.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/storage/home_storage.dart';

void main() {
  test('load follows AppStorage home when rootDir is not overridden', () async {
    final rootA = await Directory.systemTemp.createTemp('ssh_profiles_a_');
    final rootB = await Directory.systemTemp.createTemp('ssh_profiles_b_');
    addTearDown(() async {
      if (await rootA.exists()) await rootA.delete(recursive: true);
      if (await rootB.exists()) await rootB.delete(recursive: true);
      resetTestHomeStorage();
      AppPathsBootstrapper.resetForTesting();
    });

    final storage = bindTestNativeHome(rootA.path);

    const profile = SshProfile(
      id: 'p1',
      name: 'Server A',
      host: 'example.com',
      username: 'user',
    );
    final repo = SshProfileRepository(storage: storage);
    await repo.save(profile);
    expect(await repo.loadAll(), hasLength(1));

    await storage.swap(testRuntimeContext(rootB.path));

    expect(await repo.loadAll(), isEmpty);

    await storage.swap(testRuntimeContext(rootA.path));

    expect(await repo.loadAll(), hasLength(1));
    expect((await repo.loadAll()).single.name, 'Server A');
  });

  test('explicit rootDir override stays pinned', () async {
    final pinnedRoot = await Directory.systemTemp.createTemp(
      'ssh_profiles_pin_',
    );
    final otherRoot = await Directory.systemTemp.createTemp('other_root_');
    addTearDown(() async {
      if (await pinnedRoot.exists()) await pinnedRoot.delete(recursive: true);
      if (await otherRoot.exists()) await otherRoot.delete(recursive: true);
      resetTestHomeStorage();
      AppPathsBootstrapper.resetForTesting();
    });

    final repo = SshProfileRepository(rootDir: pinnedRoot.path, storage: fakeHomeStorage(), );
    await repo.save(
      const SshProfile(
        id: 'p1',
        name: 'Pinned',
        host: 'example.com',
        username: 'user',
      ),
    );

    bindTestNativeHome(otherRoot.path);

    expect(await repo.loadAll(), hasLength(1));
    expect((await repo.loadAll()).single.name, 'Pinned');
  });
  test('a dropped transport fails loud instead of reporting no profiles', () async {
    final fs = _TransportFailingFilesystem();
    final repo = SshProfileRepository(
      rootDir: '/tp',
      storage: HomeStorage.forTesting(
        filesystem: fs,
        paths: const AppPaths('/tp'),
      ),
    );

    // The file exists; reading it hits a closed SFTP channel.
    await expectLater(repo.loadAll(), throwsA(isA<StateError>()));
  });

  test('corrupt profile JSON still degrades to an empty list', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/tp/ssh-profiles.json', '{not json');
    final repo = SshProfileRepository(
      rootDir: '/tp',
      storage: HomeStorage.forTesting(
        filesystem: fs,
        paths: const AppPaths('/tp'),
      ),
    );

    expect(await repo.loadAll(), isEmpty);
  });
}

/// Filesystem whose reads fail the way a closed dartssh2 channel does.
class _TransportFailingFilesystem extends InMemoryFilesystem {
  @override
  Future<FsStat> stat(String path) async =>
      const FsStat(kind: FsEntityKind.file);

  @override
  Future<String?> readString(String path) async =>
      throw StateError('SSH client closed');
}

