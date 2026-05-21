import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/app_storage.dart';
import 'package:teampilot/services/runtime_storage_context.dart';

void main() {
  test('load follows RuntimeStorageContext when rootDir is not overridden', () async {
    final rootA = await Directory.systemTemp.createTemp('ssh_profiles_a_');
    final rootB = await Directory.systemTemp.createTemp('ssh_profiles_b_');
    addTearDown(() async {
      if (await rootA.exists()) await rootA.delete(recursive: true);
      if (await rootB.exists()) await rootB.delete(recursive: true);
      RuntimeStorageContext.resetForTesting();
      AppPathsBootstrapper.resetForTesting();
    });

    await RuntimeStorageContext.install(
      isSshMode: false,
      nativeAppDataPath: rootA.path,
      nativeHome: rootA.path,
      nativeCwd: rootA.path,
    );

    const profile = SshProfile(
      id: 'p1',
      name: 'Server A',
      host: 'example.com',
      username: 'user',
    );
    final repo = SshProfileRepository();
    await repo.save(profile);
    expect(await repo.loadAll(), hasLength(1));

    await RuntimeStorageContext.install(
      isSshMode: false,
      nativeAppDataPath: rootB.path,
      nativeHome: rootB.path,
      nativeCwd: rootB.path,
    );

    expect(await repo.loadAll(), isEmpty);

    await RuntimeStorageContext.install(
      isSshMode: false,
      nativeAppDataPath: rootA.path,
      nativeHome: rootA.path,
      nativeCwd: rootA.path,
    );

    expect(await repo.loadAll(), hasLength(1));
    expect((await repo.loadAll()).single.name, 'Server A');
  });

  test('explicit rootDir override stays pinned', () async {
    final pinnedRoot = await Directory.systemTemp.createTemp('ssh_profiles_pin_');
    final otherRoot = await Directory.systemTemp.createTemp('other_root_');
    addTearDown(() async {
      if (await pinnedRoot.exists()) await pinnedRoot.delete(recursive: true);
      if (await otherRoot.exists()) await otherRoot.delete(recursive: true);
      RuntimeStorageContext.resetForTesting();
      AppPathsBootstrapper.resetForTesting();
    });

    final repo = SshProfileRepository(rootDir: pinnedRoot.path);
    await repo.save(
      const SshProfile(
        id: 'p1',
        name: 'Pinned',
        host: 'example.com',
        username: 'user',
      ),
    );

    await RuntimeStorageContext.install(
      isSshMode: false,
      nativeAppDataPath: otherRoot.path,
      nativeHome: pinnedRoot.path,
      nativeCwd: pinnedRoot.path,
    );

    expect(await repo.loadAll(), hasLength(1));
    expect((await repo.loadAll()).single.name, 'Pinned');
  });
}
