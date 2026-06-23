import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import '../support/test_runtime_context.dart';

void main() {
  test('load follows AppStorage home when rootDir is not overridden', () async {
    final rootA = await Directory.systemTemp.createTemp('ssh_profiles_a_');
    final rootB = await Directory.systemTemp.createTemp('ssh_profiles_b_');
    addTearDown(() async {
      if (await rootA.exists()) await rootA.delete(recursive: true);
      if (await rootB.exists()) await rootB.delete(recursive: true);
      AppStorage.resetForTesting();
      AppPathsBootstrapper.resetForTesting();
    });

    bindTestNativeHome(rootA.path);

    const profile = SshProfile(
      id: 'p1',
      name: 'Server A',
      host: 'example.com',
      username: 'user',
    );
    final repo = SshProfileRepository();
    await repo.save(profile);
    expect(await repo.loadAll(), hasLength(1));

    bindTestNativeHome(rootB.path);

    expect(await repo.loadAll(), isEmpty);

    bindTestNativeHome(rootA.path);

    expect(await repo.loadAll(), hasLength(1));
    expect((await repo.loadAll()).single.name, 'Server A');
  });

  test('explicit rootDir override stays pinned', () async {
    final pinnedRoot = await Directory.systemTemp.createTemp('ssh_profiles_pin_');
    final otherRoot = await Directory.systemTemp.createTemp('other_root_');
    addTearDown(() async {
      if (await pinnedRoot.exists()) await pinnedRoot.delete(recursive: true);
      if (await otherRoot.exists()) await otherRoot.delete(recursive: true);
      AppStorage.resetForTesting();
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

    bindTestNativeHome(otherRoot.path);

    expect(await repo.loadAll(), hasLength(1));
    expect((await repo.loadAll()).single.name, 'Pinned');
  });
}
