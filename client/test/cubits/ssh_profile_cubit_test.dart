import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/cli/remote_cli_path_cache.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import '../support/test_runtime_context.dart';
import '../support/in_memory_filesystem.dart';

/// Lets fire-and-forget discovery (unawaited from `load`/`selectProfile`)
/// finish its microtask chain before assertions.
Future<void> flushDiscovery() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('concurrent load() runs the repository load once', () async {
    final repo = _SlowFakeSshProfileRepository();
    final cubit = SshProfileCubit(
      profileRepository: repo,
      credentialStore: InMemorySshCredentialStore(),
    );
    addTearDown(cubit.close);

    await Future.wait([cubit.load(), cubit.load(), cubit.load()]);

    expect(repo.loadAllCalls, 1);
    expect(cubit.state.isLoading, false);
    expect(cubit.state.profiles, hasLength(1));
  });

  test(
    'load() after a completed load starts a fresh repository read',
    () async {
      final repo = _SlowFakeSshProfileRepository();
      final cubit = SshProfileCubit(
        profileRepository: repo,
        credentialStore: InMemorySshCredentialStore(),
      );
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.load();

      expect(repo.loadAllCalls, 2);
    },
  );

  test('selected SSH profile persists across cubit reloads', () async {
    final temp = await Directory.systemTemp.createTemp(
      'ssh_profile_cubit_test_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final repository = SshProfileRepository(
      rootDir: temp.path,
      storage: fakeHomeStorage(),
    );
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

    final repository = SshProfileRepository(
      rootDir: temp.path,
      storage: fakeHomeStorage(),
    );
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
    await flushDiscovery();

    expect(appliedCli, CliTool.flashskyai);
    expect(appliedPath, '/remote/bin/flashskyai');
  });

  test('load() does not block on remote CLI discovery', () async {
    final repo = _SlowFakeSshProfileRepository();
    final cubit = SshProfileCubit(
      profileRepository: repo,
      credentialStore: InMemorySshCredentialStore(),
      locateRemoteCliPaths: (_) => Completer<Map<CliTool, String>>().future,
      onRemoteCliLocated: (_, _) async {},
      enableRemoteCliDiscovery: () => true,
    );
    addTearDown(cubit.close);

    await cubit.load().timeout(const Duration(seconds: 1));

    expect(cubit.state.isLoading, false);
    expect(cubit.state.profiles, hasLength(1));
  });

  test('cached remote CLI paths apply without calling the locator', () async {
    final repo = _SlowFakeSshProfileRepository();
    final fs = InMemoryFilesystem();
    final cache = RemoteCliPathCache(
      fs: fs,
      filePath: '/app-data/remote-cli-paths.json',
    );
    await cache.save('p1', const {CliTool.claude: '/remote/bin/claude'});

    var locateCalls = 0;
    final applied = <CliTool, String>{};
    final cubit = SshProfileCubit(
      profileRepository: repo,
      credentialStore: InMemorySshCredentialStore(),
      remoteCliPathCache: cache,
      locateRemoteCliPaths: (_) async {
        locateCalls++;
        return const {CliTool.claude: '/fresh/claude'};
      },
      onRemoteCliLocated: (cli, path) async {
        applied[cli] = path;
      },
      enableRemoteCliDiscovery: () => true,
    );
    addTearDown(cubit.close);

    await cubit.load();
    await flushDiscovery();

    expect(locateCalls, 0);
    expect(applied, const {CliTool.claude: '/remote/bin/claude'});
  });

  test('discovery miss locates, caches, then applies', () async {
    final repo = _SlowFakeSshProfileRepository();
    final fs = InMemoryFilesystem();
    final cache = RemoteCliPathCache(
      fs: fs,
      filePath: '/app-data/remote-cli-paths.json',
    );

    final applied = <CliTool, String>{};
    final cubit = SshProfileCubit(
      profileRepository: repo,
      credentialStore: InMemorySshCredentialStore(),
      remoteCliPathCache: cache,
      locateRemoteCliPaths: (_) async {
        return const {CliTool.claude: '/remote/bin/claude'};
      },
      onRemoteCliLocated: (cli, path) async {
        applied[cli] = path;
      },
      enableRemoteCliDiscovery: () => true,
    );
    addTearDown(cubit.close);

    await cubit.load();
    await flushDiscovery();

    expect(applied, const {CliTool.claude: '/remote/bin/claude'});
    expect(await cache.load('p1'), const {
      CliTool.claude: '/remote/bin/claude',
    });
  });

  test(
    'saveProfile invalidates the cache when the connection fingerprint changes',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'ssh_profile_cubit_invalidate_',
      );
      addTearDown(() => temp.delete(recursive: true));

      const profile = SshProfile(
        id: 'p1',
        name: 'one',
        host: 'one.example.com',
        username: 'alice',
      );
      final repository = SshProfileRepository(
        rootDir: temp.path,
        storage: fakeHomeStorage(),
      );
      await repository.save(profile);

      final cache = RemoteCliPathCache(
        fs: InMemoryFilesystem(),
        filePath: '/app-data/remote-cli-paths.json',
      );
      await cache.save('p1', const {CliTool.claude: '/remote/bin/claude'});

      final cubit = SshProfileCubit(
        profileRepository: repository,
        credentialStore: InMemorySshCredentialStore(),
        remoteCliPathCache: cache,
      );
      addTearDown(cubit.close);

      await cubit.load();

      await cubit.saveProfile(
        const SshProfile(
          id: 'p1',
          name: 'one',
          host: 'two.example.com',
          username: 'alice',
        ),
      );

      expect(await cache.load('p1'), isEmpty);
    },
  );

  test('saveProfile keeps the cache when only display fields change', () async {
    final temp = await Directory.systemTemp.createTemp(
      'ssh_profile_cubit_keep_cache_',
    );
    addTearDown(() => temp.delete(recursive: true));

    const profile = SshProfile(
      id: 'p1',
      name: 'one',
      host: 'one.example.com',
      username: 'alice',
    );
    final repository = SshProfileRepository(
      rootDir: temp.path,
      storage: fakeHomeStorage(),
    );
    await repository.save(profile);

    final cache = RemoteCliPathCache(
      fs: InMemoryFilesystem(),
      filePath: '/app-data/remote-cli-paths.json',
    );
    await cache.save('p1', const {CliTool.claude: '/remote/bin/claude'});

    final cubit = SshProfileCubit(
      profileRepository: repository,
      credentialStore: InMemorySshCredentialStore(),
      remoteCliPathCache: cache,
    );
    addTearDown(cubit.close);

    await cubit.load();

    await cubit.saveProfile(
      const SshProfile(
        id: 'p1',
        name: 'renamed',
        host: 'one.example.com',
        username: 'alice',
      ),
    );

    expect(await cache.load('p1'), const {
      CliTool.claude: '/remote/bin/claude',
    });
  });

  test(
    'stale in-flight discovery does not re-cache or apply after saveProfile',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'ssh_profile_cubit_stale_save_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final repository = SshProfileRepository(
        rootDir: temp.path,
        storage: fakeHomeStorage(),
      );
      await repository.save(
        const SshProfile(
          id: 'p1',
          name: 'one',
          host: 'one.example.com',
          username: 'alice',
        ),
      );

      final cache = RemoteCliPathCache(
        fs: InMemoryFilesystem(),
        filePath: '/app-data/remote-cli-paths.json',
      );
      final locator = _ScriptedRemoteCliLocator();
      final applied = <String>[];
      final cubit = SshProfileCubit(
        profileRepository: repository,
        credentialStore: InMemorySshCredentialStore(),
        remoteCliPathCache: cache,
        locateRemoteCliPaths: locator.call,
        onRemoteCliLocated: (cli, path) async {
          applied.add('${cli.name}:$path');
        },
        enableRemoteCliDiscovery: () => true,
      );
      addTearDown(cubit.close);

      // Discovery for the old host is now in flight (gen 0).
      await cubit.load();
      await flushDiscovery();
      expect(locator.pending, hasLength(1));

      // Changing the host invalidates the cache and bumps the generation;
      // the reload starts a fresh discovery (gen 1) that also stays pending.
      await cubit.saveProfile(
        const SshProfile(
          id: 'p1',
          name: 'one',
          host: 'two.example.com',
          username: 'alice',
        ),
      );
      await flushDiscovery();
      expect(locator.pending, hasLength(2));

      // The old probe completes last with old-host paths: it must neither
      // save them into the (just invalidated) cache nor apply them.
      locator.pending[0].complete(const {
        CliTool.claude: '/old-host/bin/claude',
      });
      await flushDiscovery();

      expect(await cache.load('p1'), isEmpty);
      expect(applied, isEmpty);

      // The fresh discovery for the new host applies normally.
      locator.pending[1].complete(const {
        CliTool.claude: '/new-host/bin/claude',
      });
      await flushDiscovery();

      expect(applied, ['claude:/new-host/bin/claude']);
      expect(await cache.load('p1'), const {
        CliTool.claude: '/new-host/bin/claude',
      });
    },
  );

  test(
    'out-of-order discoveries only apply the selected profile paths',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'ssh_profile_cubit_stale_select_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final repository = SshProfileRepository(
        rootDir: temp.path,
        storage: fakeHomeStorage(),
      );
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

      final locator = _ScriptedRemoteCliLocator();
      final applied = <String>[];
      final cubit = SshProfileCubit(
        profileRepository: repository,
        credentialStore: InMemorySshCredentialStore(),
        locateRemoteCliPaths: locator.call,
        onRemoteCliLocated: (cli, path) async {
          applied.add('${cli.name}:$path');
        },
        enableRemoteCliDiscovery: () => true,
      );
      addTearDown(cubit.close);

      // p1 is selected by default; its discovery stays pending.
      await cubit.load();
      await flushDiscovery();
      expect(locator.pending, hasLength(1));

      // Selecting p2 supersedes p1's discovery; p2's discovery completes.
      await cubit.selectProfile('p2');
      await flushDiscovery();
      expect(locator.pending, hasLength(2));
      locator.pending[1].complete(const {CliTool.claude: '/p2/bin/claude'});
      await flushDiscovery();

      expect(applied, ['claude:/p2/bin/claude']);

      // p1's late result must not interleave or overwrite p2's applied paths.
      locator.pending[0].complete(const {CliTool.claude: '/p1/bin/claude'});
      await flushDiscovery();

      expect(applied, ['claude:/p2/bin/claude']);
      expect(applied, hasLength(1));
    },
  );

  test(
    'deleteProfile removes profile even when credential cleanup fails',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'ssh_profile_cubit_delete_creds_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final repository = SshProfileRepository(
        rootDir: temp.path,
        storage: fakeHomeStorage(),
      );
      await repository.save(
        const SshProfile(
          id: 'p1',
          name: 'one',
          host: 'one.example.com',
          username: 'alice',
        ),
      );

      final cubit = SshProfileCubit(
        profileRepository: repository,
        credentialStore: _ThrowingCredentialStore(),
      );
      addTearDown(cubit.close);

      await cubit.load();
      expect(cubit.state.profiles, hasLength(1));

      await cubit.deleteProfile('p1');

      expect(cubit.state.profiles, isEmpty);
      expect(await repository.loadAll(), isEmpty);
    },
  );

  test(
    'load follows AppStorage home when repository root is dynamic',
    () async {
      final rootA = await Directory.systemTemp.createTemp('ssh_cubit_a_');
      final rootB = await Directory.systemTemp.createTemp('ssh_cubit_b_');
      addTearDown(() async {
        if (await rootA.exists()) await rootA.delete(recursive: true);
        if (await rootB.exists()) await rootB.delete(recursive: true);
        resetTestHomeStorage();
        AppPathsBootstrapper.resetForTesting();
      });

      final storage = bindTestNativeHome(rootA.path);

      final repository = SshProfileRepository(storage: storage);
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
      await cubit.load();
      expect(cubit.state.profiles, hasLength(1));

      await storage.swap(testRuntimeContext(rootB.path));

      await cubit.load();
      expect(cubit.state.profiles, isEmpty);
    },
  );

  test('updatePathCache saves without invalidateProfileConnection', () async {
    final temp = await Directory.systemTemp.createTemp(
      'ssh_profile_cubit_path_cache_',
    );
    addTearDown(() => temp.delete(recursive: true));

    const profileId = 'p1';
    final repository = SshProfileRepository(
      rootDir: temp.path,
      storage: fakeHomeStorage(),
    );
    await repository.save(
      const SshProfile(
        id: profileId,
        name: 'one',
        host: 'one.example.com',
        username: 'alice',
      ),
    );

    final invalidateCalls = <String>[];
    final cubit = SshProfileCubit(
      profileRepository: repository,
      credentialStore: InMemorySshCredentialStore(),
      invalidateProfileConnection: invalidateCalls.add,
    );
    addTearDown(cubit.close);

    await cubit.load();
    await cubit.updatePathCache(
      profileId,
      home: '/home/u',
      appDataRoot: '/home/u/.teampilot',
    );

    expect(invalidateCalls, isEmpty);
    final saved = await repository.loadAll();
    expect(saved.single.lastHome, '/home/u');
    expect(saved.single.lastAppDataRoot, '/home/u/.teampilot');
    expect(cubit.state.profiles.single.lastHome, '/home/u');
  });

  test(
    'selectProfile updates selection without home-plane side effects',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'ssh_profile_cubit_select_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final repository = SshProfileRepository(
        rootDir: temp.path,
        storage: fakeHomeStorage(),
      );
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

      final cubit = SshProfileCubit(
        profileRepository: repository,
        credentialStore: InMemorySshCredentialStore(),
      );
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.selectProfile('p2');

      expect(cubit.state.selectedProfileId, 'p2');
      expect(await repository.loadSelectedProfileId(), 'p2');
    },
  );
}

class _ScriptedRemoteCliLocator {
  final pending = <Completer<Map<CliTool, String>>>[];

  Future<Map<CliTool, String>> call(SshProfile profile) {
    final completer = Completer<Map<CliTool, String>>();
    pending.add(completer);
    return completer.future;
  }
}

class _SlowFakeSshProfileRepository implements SshProfileRepository {
  int loadAllCalls = 0;

  static const _profile = SshProfile(
    id: 'p1',
    name: 'one',
    host: 'one.example.com',
    username: 'alice',
  );

  @override
  Future<List<SshProfile>> loadAll() async {
    loadAllCalls++;
    // Simulates the real IO read window during which concurrent callers pile
    // up before the single-flight fix coalesces them.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return const [_profile];
  }

  @override
  Future<String> loadSelectedProfileId() async => '';

  @override
  Future<void> save(SshProfile profile) async {}

  @override
  Future<void> saveAll(List<SshProfile> profiles) async {}

  @override
  Future<void> saveSelectedProfileId(String profileId) async {}

  @override
  Future<void> delete(String profileId) async {}

  @override
  Future<SshProfile?> findById(String profileId) async =>
      profileId == 'p1' ? _profile : null;
}

class _ThrowingCredentialStore implements SshCredentialStore {
  @override
  Future<void> deleteAll(String profileId) async {
    throw StateError('KeyringLocked');
  }

  @override
  Future<String?> loadPassword(String profileId) async => null;

  @override
  Future<String?> loadPrivateKey(String profileId) async => null;

  @override
  Future<String?> loadPrivateKeyPassphrase(String profileId) async => null;

  @override
  Future<void> savePassword(String profileId, String password) async {}

  @override
  Future<void> savePrivateKey(String profileId, String privateKey) async {}

  @override
  Future<void> savePrivateKeyPassphrase(
    String profileId,
    String passphrase,
  ) async {}

  @override
  Future<String?> loadDevicePrivateKey() async => null;

  @override
  Future<void> saveDevicePrivateKey(String privateKey) async {}

  @override
  Future<String?> loadRelayGrant(String profileId) async => null;

  @override
  Future<void> saveRelayGrant(String profileId, String grant) async {}
}
