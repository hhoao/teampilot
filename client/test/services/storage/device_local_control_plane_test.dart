import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/device_local_control_plane.dart';
import 'package:teampilot/services/storage/targets_repository.dart';
import '../../support/test_runtime_context.dart';

void main() {
  test('SSH profile catalog survives AppStorage rebind to empty home', () async {
    final native = await Directory.systemTemp.createTemp('native_ctrl_');
    final remote = await Directory.systemTemp.createTemp('remote_home_');
    addTearDown(() async {
      if (await native.exists()) await native.delete(recursive: true);
      if (await remote.exists()) await remote.delete(recursive: true);
      AppStorage.resetForTesting();
      AppPathsBootstrapper.resetForTesting();
    });

    bindTestNativeHome(native.path);

    final repo = deviceLocalSshProfileRepository(native.path);
    await repo.save(
      const SshProfile(
        id: 'p1',
        name: 'Phone profile',
        host: 'example.com',
        username: 'user',
      ),
    );
    expect(await repo.loadAll(), hasLength(1));

    // Android Connect switches home onto remote AppStorage; remote catalog is empty.
    bindTestNativeHome(remote.path);

    expect(await repo.loadAll(), hasLength(1));
    expect((await repo.loadAll()).single.id, 'p1');
  });

  test('targets.json survives AppStorage rebind to empty home', () async {
    final native = await Directory.systemTemp.createTemp('native_tgt_');
    final remote = await Directory.systemTemp.createTemp('remote_tgt_');
    addTearDown(() async {
      if (await native.exists()) await native.delete(recursive: true);
      if (await remote.exists()) await remote.delete(recursive: true);
      AppStorage.resetForTesting();
      AppPathsBootstrapper.resetForTesting();
    });

    bindTestNativeHome(native.path);

    final repo = deviceLocalTargetsRepository(native.path);
    await repo.save(
      TargetsRegistryFile(
        targets: [RuntimeTarget.ssh('p1', label: 'box')],
      ),
    );
    expect((await repo.load()).targets, hasLength(1));

    bindTestNativeHome(remote.path);

    expect((await repo.load()).targets, hasLength(1));
    expect((await repo.load()).targets.single.sshProfileId, 'p1');
  });
}
