import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/connection/device_connection.dart';
import 'package:teampilot/models/connection/machine_id.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/repositories/connection_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/connect/profile_connection_mapping.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import '../support/test_runtime_context.dart';
import '../support/in_memory_filesystem.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/storage/home_storage.dart';

import '../support/connection_fixtures.dart';

void main() {
  test('load follows AppStorage home when rootDir is not overridden', () async {
    final rootA = await Directory.systemTemp.createTemp('ssh_profiles_a_');
    final rootB = await Directory.systemTemp.createTemp('ssh_profiles_b_');
    addTearDown(() async {
      if (await rootA.exists()) await rootA.delete(recursive: true);
      if (await rootB.exists()) await rootB.delete(recursive: true);
      resetTestHomeStorage();
      AppPathsBootstrapper.resetForTesting();
    });

    final storage = bindTestNativeHome(rootA.path);

    const profile = SshProfile(
      id: 'p1',
      name: 'Server A',
      host: 'example.com',
      username: 'user',
    );
    final repo = SshProfileRepository(storage: storage);
    await repo.save(profile);
    expect(await repo.loadAll(), hasLength(1));

    await storage.swap(testRuntimeContext(rootB.path));

    expect(await repo.loadAll(), isEmpty);

    await storage.swap(testRuntimeContext(rootA.path));

    expect(await repo.loadAll(), hasLength(1));
    expect((await repo.loadAll()).single.name, 'Server A');
  });

  test('explicit rootDir override stays pinned', () async {
    final pinnedRoot = await Directory.systemTemp.createTemp(
      'ssh_profiles_pin_',
    );
    final otherRoot = await Directory.systemTemp.createTemp('other_root_');
    addTearDown(() async {
      if (await pinnedRoot.exists()) await pinnedRoot.delete(recursive: true);
      if (await otherRoot.exists()) await otherRoot.delete(recursive: true);
      resetTestHomeStorage();
      AppPathsBootstrapper.resetForTesting();
    });

    final repo = SshProfileRepository(
      rootDir: pinnedRoot.path,
      storage: fakeHomeStorage(),
    );
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

  test(
    'a dropped transport fails loud instead of reporting no profiles',
    () async {
      final fs = _TransportFailingFilesystem();
      final repo = SshProfileRepository(
        rootDir: '/tp',
        storage: HomeStorage.forTesting(
          filesystem: fs,
          paths: const AppPaths('/tp'),
        ),
      );

      // The file exists; reading it hits a closed SFTP channel.
      await expectLater(repo.loadAll(), throwsA(isA<StateError>()));
    },
  );

  test('corrupt profile JSON still degrades to an empty list', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/tp/ssh-profiles.json', '{not json');
    final repo = SshProfileRepository(
      rootDir: '/tp',
      storage: HomeStorage.forTesting(
        filesystem: fs,
        paths: const AppPaths('/tp'),
      ),
    );

    expect(await repo.loadAll(), isEmpty);
  });

  test('projects a connection into a runtime SshProfile', () {
    const lan = SshReachabilityEndpoint(
      kind: SshEndpointKind.lan,
      host: 'h',
      port: 2222,
    );
    const extra = SshReachabilityEndpoint(
      kind: SshEndpointKind.extra,
      host: '203.0.113.9',
      port: 22,
    );
    final connection = deviceConnection(
      machineId: 't1',
      displayName: 'dev',
      username: 'u',
      authType: SshAuthType.privateKey,
      credentialRef: 'vault-1',
      endpoints: const [lan, extra],
      preferredKind: SshEndpointKind.extra,
      fingerprints: const ['SHA256:abc'],
      paths: const HomePathCache(home: '/home/u', appDataRoot: '/data/u'),
      embeddedTarget: true,
      relayUrl: 'wss://relay.example.com',
      pairedDesktopId: 'desktop-1',
      updatedAt: 10,
    );

    final profile = profileFromConnection(connection);

    expect(profile.id, 't1');
    expect(profile.name, 'dev');
    // The address is the preferred endpoint, not an independent stored host.
    expect(profile.host, '203.0.113.9');
    expect(profile.port, 22);
    expect(profile.username, 'u');
    expect(profile.authType, SshAuthType.privateKey);
    expect(profile.createdAt, 10);
    expect(profile.updatedAt, 10);
    expect(profile.vaultEntryId, 'vault-1');
    expect(profile.endpoints, [lan, extra]);
    expect(profile.hostKeyFingerprints, ['SHA256:abc']);
    expect(profile.lastGoodKind, SshEndpointKind.extra);
    expect(profile.lastHome, '/home/u');
    expect(profile.lastAppDataRoot, '/data/u');
    expect(profile.embeddedTarget, isTrue);
    expect(profile.relayUrl, 'wss://relay.example.com');
    expect(profile.pairedDesktopId, 'desktop-1');
  });

  test('facade delegates to an explicit ConnectionStore', () async {
    final (repo, store) = _facadePair();

    expect(identical(repo.connectionStore, store), isTrue);

    await repo.save(
      const SshProfile(
        id: 'p1',
        name: 'dev',
        host: 'h',
        username: 'u',
        embeddedTarget: true,
      ),
    );

    final connections = await store.loadAll();
    expect(connections, hasLength(1));
    expect(connections.single.machineId.value, 'p1');
    expect(connections.single.plan.embeddedTarget, isTrue);
    expect(connections.single.updatedAt, greaterThan(0));

    final profiles = await repo.loadAll();
    expect(profiles.single.id, 'p1');
    expect(profiles.single.embeddedTarget, isTrue);
  });

  test(
    'facade save clears nullable fields when updating an existing connection',
    () async {
      final (repo, store) = _facadePair();

      await store.save(
        deviceConnection(
          machineId: 'p1',
          credentialRef: 'vault-1',
          relayUrl: 'wss://old',
          pairedDesktopId: 'desktop-1',
          paths: const HomePathCache(home: '/old/home', appDataRoot: '/old/data'),
          preferredKind: SshEndpointKind.extra,
        ),
      );

      await repo.save(
        const SshProfile(id: 'p1', name: 'dev2', host: 'h2', username: 'u2'),
      );

      final connection = (await store.loadAll()).single;
      expect(connection.displayName, 'dev2');
      expect(connection.plan.credentialRef, isNull);
      expect(connection.plan.relayUrl, isNull);
      expect(connection.pairedDesktopId, isNull);
      expect(connection.paths, isNull);
      expect(connection.preferredKind, isNull);
      expect(connection.updatedAt, greaterThan(0));

      final profile = (await repo.loadAll()).single;
      expect(profile.vaultEntryId, isNull);
      expect(profile.relayUrl, isNull);
      expect(profile.lastGoodKind, isNull);
    },
  );

  test('a manual address fix keeps the rest of the address plan', () async {
    final (repo, store) = _facadePair();
    await store.save(
      deviceConnection(
        machineId: 'p1',
        endpoints: const [
          SshReachabilityEndpoint(kind: SshEndpointKind.lan, host: 'old', port: 22),
          SshReachabilityEndpoint(
            kind: SshEndpointKind.extra,
            host: '203.0.113.9',
            port: 22,
          ),
        ],
      ),
    );

    await repo.save(
      const SshProfile(id: 'p1', name: 'dev', host: 'new', username: 'u'),
    );

    final connection = (await store.loadAll()).single;
    expect(connection.plan.endpoints.map((e) => e.host), ['new', '203.0.113.9']);
  });

  test('a relay win never changes the address plan or its generation', () async {
    final (repo, store) = _facadePair();
    const lan = SshReachabilityEndpoint(
      kind: SshEndpointKind.lan,
      host: 'h',
      port: 22,
    );
    await store.save(
      deviceConnection(
        machineId: 'p1',
        endpoints: const [lan],
        preferredKind: SshEndpointKind.lan,
      ),
    );
    final before = (await store.loadAll()).single;

    // PairedConnectAttempt persists a relay win as lastGoodKind=relay while the
    // stored host/port stay put.
    await repo.save(
      const SshProfile(
        id: 'p1',
        name: 'dev',
        host: 'h',
        username: 'u',
        lastGoodKind: SshEndpointKind.relay,
      ),
    );

    final after = (await store.loadAll()).single;
    expect(after.preferredKind, SshEndpointKind.relay);
    expect(after.plan.endpoints, const [lan]);
    expect(after.generation, before.generation);
  });

  test(
    'facade saveAll, findById and delete delegate to the connection store',
    () async {
      final (repo, store) = _facadePair();

      await repo.saveAll(const [
        SshProfile(id: 'a', name: 'A', host: 'ha', username: 'ua'),
        SshProfile(id: 'b', name: 'B', host: 'hb', username: 'ub'),
      ]);
      expect(await store.loadAll(), hasLength(2));

      final found = await repo.findById('a');
      expect(found?.name, 'A');
      expect(await repo.findById('missing'), isNull);

      await repo.delete('a');
      expect(await store.loadAll(), hasLength(1));
      expect(await repo.findById('a'), isNull);
      expect(await store.findById(const MachineId('a')), isNull);
      expect((await repo.loadAll()).single.id, 'b');
    },
  );

  test('facade save persists local-only fields', () async {
    final (repo, store) = _facadePair();

    await repo.save(
      const SshProfile(
        id: 'p1',
        name: 'dev',
        host: 'h',
        username: 'u',
        vaultEntryId: 'vault-1',
        lastHome: '/home/u',
        lastAppDataRoot: '/data/u',
      ),
    );

    final connection = (await store.loadAll()).single;
    expect(connection.plan.credentialRef, 'vault-1');
    expect(connection.paths?.home, '/home/u');
    expect(connection.paths?.appDataRoot, '/data/u');
    expect(connection.updatedAt, greaterThan(0));
  });

  test('legacy repo getter throws a clear StateError', () async {
    final repo = SshProfileRepository(storage: fakeHomeStorage());

    // Legacy profiles.json behavior is still intact.
    await repo.save(
      const SshProfile(id: 'p1', name: 'dev', host: 'h', username: 'u'),
    );
    expect(await repo.loadAll(), hasLength(1));

    expect(
      () => repo.connectionStore,
      throwsA(
        predicate<Object>(
          (error) =>
              error is StateError &&
              error.message.contains('ConnectionStore'),
        ),
      ),
    );
  });
}

(SshProfileRepository, ConnectionStore) _facadePair() {
  final fs = InMemoryFilesystem();
  final store = ConnectionStore(rootDir: '/tp/ssh_profiles', fs: fs);
  final repo = SshProfileRepository(
    connections: store,
    storage: fakeHomeStorage(filesystem: fs),
  );
  return (repo, store);
}

/// Filesystem whose reads fail the way a closed dartssh2 channel does.
class _TransportFailingFilesystem extends InMemoryFilesystem {
  @override
  Future<FsStat> stat(String path) async =>
      const FsStat(kind: FsEntityKind.file);

  @override
  Future<String?> readString(String path) async =>
      throw StateError('SSH client closed');
}
