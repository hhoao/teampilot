import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ssh_server_config_cubit.dart';
import 'package:teampilot/models/ssh_server_profile.dart';
import 'package:teampilot/repositories/ssh_server_profile_repository.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  late SshServerProfileRepository repo;

  setUp(() {
    final fs = InMemoryFilesystem();
    repo = SshServerProfileRepository(storage: fakeHomeStorage(filesystem: fs));
  });

  test('loads server profiles from repository', () async {
    final cubit = SshServerConfigCubit(repository: repo);
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.profiles, isEmpty);
  });

  test(
    'save persists the profile through the repository and reloads state',
    () async {
      final cubit = SshServerConfigCubit(repository: repo);
      addTearDown(cubit.close);
      const profile = SshServerProfile(
        id: 's1',
        name: 'dev',
        host: 'dev.example.com',
        username: 'alice',
      );

      await cubit.save(profile);

      expect(cubit.state.profiles, [profile]);
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.error, isNull);
      expect(await repo.findById('s1'), profile);
    },
  );

  test(
    'delete removes the profile through the repository and reloads state',
    () async {
      final cubit = SshServerConfigCubit(repository: repo);
      addTearDown(cubit.close);
      const dev = SshServerProfile(
        id: 's1',
        name: 'dev',
        host: 'dev.example.com',
        username: 'alice',
      );
      const prod = SshServerProfile(
        id: 's2',
        name: 'prod',
        host: 'prod.example.com',
        username: 'bob',
      );
      await cubit.save(dev);
      await cubit.save(prod);
      expect(cubit.state.profiles, hasLength(2));

      await cubit.delete('s1');

      expect(cubit.state.profiles, [prod]);
      expect(await repo.findById('s1'), isNull);
      expect(await repo.findById('s2'), prod);
    },
  );
}
