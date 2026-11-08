import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/plane_ssh_profile_repository.dart';
import 'package:teampilot/repositories/ssh_server_profile_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/storage/home_storage.dart';

import '../support/post_frame_test_harness.dart';
import '../support/test_runtime_context.dart';

void main() {
  late Directory planeDir;
  late HomeStorage planeStorage;

  setUp(() {
    setUpTestAppStorage();
    planeDir = Directory.systemTemp.createTempSync('test_plane_');
    planeStorage = HomeStorage(testRuntimeContext(planeDir.path));
  });

  tearDown(() {
    tearDownTestAppStorage();
    if (planeDir.existsSync()) planeDir.deleteSync(recursive: true);
  });

  PlaneSshProfileRepository buildRepo() => PlaneSshProfileRepository(
    storage: planeStorage,
    servers: SshServerProfileRepository(storage: planeStorage),
  );

  test('lists the plane catalog and ignores this device targets', () async {
    // Device-local catalog (the shared test home) holds one server.
    final deviceFs = testHomeStorage.fs;
    await _writeJson(
      deviceFs,
      deviceFs.pathContext.join(
        testHomeStorage.appDataRoot,
        'remote-targets.json',
      ),
      [_json(id: 'device-1', name: 'device-only')],
    );
    // The plane holds a different server.
    final planeFs = planeStorage.fs;
    await _writeJson(
      planeFs,
      planeFs.pathContext.join(
        planeStorage.paths.sshProfilesDir,
        'profiles.json',
      ),
      [_json(id: 'plane-1', name: 'plane-only')],
    );

    final profiles = await buildRepo().loadAll();

    expect(profiles.map((p) => p.id), ['plane-1']);
  });

  test('save writes the plane projection, never the device catalog', () async {
    final repo = buildRepo();

    await repo.save(
      const SshProfile(id: 'new-1', name: 'fresh', host: 'h', username: 'u'),
    );

    final planeFs = planeStorage.fs;
    final planeFile = await planeFs.readString(
      planeFs.pathContext.join(
        planeStorage.paths.sshProfilesDir,
        'profiles.json',
      ),
    );
    expect((jsonDecode(planeFile!) as List).length, 1);
    final deviceFs = testHomeStorage.fs;
    expect(
      (await deviceFs.stat(
        deviceFs.pathContext.join(
          testHomeStorage.appDataRoot,
          'remote-targets.json',
        ),
      )).isFile,
      isFalse,
    );
  });

  test('delete removes the plane entry', () async {
    final planeFs = planeStorage.fs;
    await _writeJson(
      planeFs,
      planeFs.pathContext.join(
        planeStorage.paths.sshProfilesDir,
        'profiles.json',
      ),
      [_json(id: 'plane-1', name: 'one'), _json(id: 'plane-2', name: 'two')],
    );
    final repo = buildRepo();

    await repo.delete('plane-1');

    expect((await repo.loadAll()).map((p) => p.id), ['plane-2']);
  });

  test('profile selection is not persisted on the plane', () async {
    final repo = buildRepo();

    expect(await repo.loadSelectedProfileId(), '');
    await repo.saveSelectedProfileId('plane-1');

    final planeFs = planeStorage.fs;
    expect(
      (await planeFs.stat(
        planeFs.pathContext.join(
          planeStorage.paths.sshProfilesDir,
          'selected_profile.txt',
        ),
      )).isFile,
      isFalse,
    );
  });
}

Future<void> _writeJson(
  Filesystem fs,
  String path,
  List<Map<String, Object?>> rows,
) async {
  await fs.ensureDir(fs.pathContext.dirname(path));
  await fs.atomicWrite(path, jsonEncode(rows));
}

Map<String, Object?> _json({required String id, required String name}) => {
  'schemaVersion': 1,
  'id': id,
  'name': name,
  'host': 'h',
  'port': 22,
  'username': 'u',
  'authType': 'password',
  'updatedAt': 10,
  'pendingSync': false,
};
