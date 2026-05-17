import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';

void main() {
  test('selected SSH profile persists across cubit reloads', () async {
    final temp = await Directory.systemTemp.createTemp(
      'ssh_profile_cubit_test_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final repository = SshProfileRepository(rootDir: temp.path);
    await repository.save(
      const SshProfile(
        id: 'p1',
        name: 'one',
        host: 'one.example.com',
        username: 'alice',
      ),
    );
    await repository.save(
      const SshProfile(
        id: 'p2',
        name: 'two',
        host: 'two.example.com',
        username: 'alice',
      ),
    );

    final firstCubit = SshProfileCubit(
      profileRepository: repository,
      credentialStore: InMemorySshCredentialStore(),
    );
    addTearDown(firstCubit.close);

    await firstCubit.load();
    await firstCubit.selectProfile('p2');

    final secondCubit = SshProfileCubit(
      profileRepository: repository,
      credentialStore: InMemorySshCredentialStore(),
    );
    addTearDown(secondCubit.close);

    await secondCubit.load();

    expect(secondCubit.state.selectedProfileId, 'p2');
    expect(secondCubit.state.selectedProfile?.host, 'two.example.com');
  });
}
