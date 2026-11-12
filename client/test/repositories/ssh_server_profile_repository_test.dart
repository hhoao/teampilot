import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_server_profile.dart';
import 'package:teampilot/repositories/ssh_server_profile_repository.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('saves and loads on the home plane', () async {
    final repo = SshServerProfileRepository(storage: testHomeStorage);
    const profile = SshServerProfile(
      id: 't1',
      name: 'dev',
      host: 'h',
      username: 'u',
    );
    await repo.save(profile);
    expect(await repo.loadAll(), [profile]);
  });

  test('writes under ssh_profiles/profiles.json', () async {
    final repo = SshServerProfileRepository(storage: testHomeStorage);
    await repo.save(
      const SshServerProfile(id: 't1', name: 'dev', host: 'h', username: 'u'),
    );
    final path = testHomeStorage.fs.pathContext.join(
      testHomeStorage.paths.sshProfilesDir,
      'profiles.json',
    );
    expect((await testHomeStorage.fs.stat(path)).isFile, isTrue);
  });

  test('ignores remote-targets.json on the home plane', () async {
    // The device-local catalog that backs "Remote connections" must never
    // leak into this page: only profiles.json is read.
    await _writePlaneTargets([
      _target(id: 't1', name: 'dev', host: 'h1', updatedAt: 10),
    ]);

    final repo = SshServerProfileRepository(storage: testHomeStorage);

    expect(await repo.loadAll(), isEmpty);
  });

  test('saving writes only profiles.json', () async {
    await _writePlaneTargets([
      _target(id: 't1', name: 'dev', host: 'h1', updatedAt: 10),
    ]);
    final repo = SshServerProfileRepository(storage: testHomeStorage);

    await repo.save(
      const SshServerProfile(
        id: 't9',
        name: 'other',
        host: 'h9',
        username: 'u',
      ),
    );

    final raw = await testHomeStorage.fs.readString(
      testHomeStorage.fs.pathContext.join(
        testHomeStorage.paths.sshProfilesDir,
        'profiles.json',
      ),
    );
    final written = (jsonDecode(raw!) as List)
        .whereType<Map<String, Object?>>()
        .map((json) => json['id'])
        .toList();
    expect(written, ['t9']);
  });
}

Map<String, Object?> _target({
  required String id,
  required String name,
  required String host,
  required int updatedAt,
}) => {
  'schemaVersion': 1,
  'id': id,
  'name': name,
  'host': host,
  'port': 22,
  'username': 'u',
  'authType': 'password',
  'updatedAt': updatedAt,
};

Future<void> _writePlaneTargets(List<Map<String, Object?>> targets) async {
  final fs = testHomeStorage.fs;
  final path = fs.pathContext.join(
    testHomeStorage.appDataRoot,
    'remote-targets.json',
  );
  await fs.atomicWrite(path, jsonEncode(targets));
}
