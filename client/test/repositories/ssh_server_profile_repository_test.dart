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
}
