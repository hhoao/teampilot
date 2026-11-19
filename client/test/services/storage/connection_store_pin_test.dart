import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/device_local_control_plane.dart';

import '../../support/connection_fixtures.dart';
import '../../support/test_runtime_context.dart';

void main() {
  test('connection store stays device-local after home rebinds to ssh', () async {
    final native = await Directory.systemTemp.createTemp('native_pin_');
    final remoteHome = await Directory.systemTemp.createTemp(
      'remote_home_pin_',
    );
    addTearDown(() async {
      if (await native.exists()) await native.delete(recursive: true);
      if (await remoteHome.exists()) await remoteHome.delete(recursive: true);
      resetTestHomeStorage();
      AppPathsBootstrapper.resetForTesting();
    });

    // Android Connect rebinds the app-scoped home plane onto the SSH host.
    // A store that rode that plane would follow it and lose the very records
    // needed to reconnect; this one must stay on the device. Bind the rebound
    // home BEFORE constructing the store so the pin is actually exercised.
    bindTestNativeHome(remoteHome.path);

    final store = deviceLocalConnectionStore(native.path);
    expect(store.fs, isA<LocalFilesystem>());
    expect(store.rootDir, native.path);

    await store.save(deviceConnection(machineId: 't1'));
    expect(await store.loadAll(), hasLength(1));
    expect(
      (await store.loadAll()).single.machineId.value,
      't1',
    );
    expect(
      File(
        store.fs.pathContext.join(native.path, 'remote-targets.json'),
      ).existsSync(),
      isTrue,
    );
    // The rebound (remote) home must never receive the catalog.
    expect(
      File(
        store.fs.pathContext.join(remoteHome.path, 'remote-targets.json'),
      ).existsSync(),
      isFalse,
    );
  });
}
