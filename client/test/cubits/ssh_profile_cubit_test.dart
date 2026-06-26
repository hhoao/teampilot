import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import '../support/test_runtime_context.dart';

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

  test('selectProfile discovers remote CLI paths on Android mode', () async {
    final temp = await Directory.systemTemp.createTemp(
      'ssh_profile_cubit_remote_cli_',
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

    CliTool? appliedCli;
    String? appliedPath;
    final cubit = SshProfileCubit(
      profileRepository: repository,
      credentialStore: InMemorySshCredentialStore(),
      locateRemoteCliPaths: (_) async => {
        CliTool.claude: '/remote/bin/claude',
        CliTool.flashskyai: '/remote/bin/flashskyai',
      },
      onRemoteCliLocated: (cli, path) async {
        appliedCli = cli;
        appliedPath = path;
      },
      enableRemoteCliDiscovery: () => true,
    );
    addTearDown(cubit.close);

    await cubit.load();
    await cubit.selectProfile('p1');

    expect(appliedCli, CliTool.flashskyai);
    expect(appliedPath, '/remote/bin/flashskyai');
  });

  test('load follows AppStorage home when repository root is dynamic', () async {
    final rootA = await Directory.systemTemp.createTemp('ssh_cubit_a_');
    final rootB = await Directory.systemTemp.createTemp('ssh_cubit_b_');
    addTearDown(() async {
      if (await rootA.exists()) await rootA.delete(recursive: true);
      if (await rootB.exists()) await rootB.delete(recursive: true);
      AppStorage.resetForTesting();
      AppPathsBootstrapper.resetForTesting();
    });

    bindTestNativeHome(rootA.path);

    final repository = SshProfileRepository();
    final cubit = SshProfileCubit(
      profileRepository: repository,
      credentialStore: InMemorySshCredentialStore(),
    );
    addTearDown(cubit.close);

    await repository.save(
      const SshProfile(
        id: 'p1',
        name: 'Server A',
        host: 'example.com',
        username: 'user',
      ),
    );
    await cubit.load(notifyActiveProfileChanged: false);
    expect(cubit.state.profiles, hasLength(1));

    bindTestNativeHome(rootB.path);

    await cubit.load(notifyActiveProfileChanged: false);
    expect(cubit.state.profiles, isEmpty);
  });
}
