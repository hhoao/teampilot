import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/remote_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/repositories/remote_target_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import '../support/test_runtime_context.dart';
import '../support/in_memory_filesystem.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/storage/home_storage.dart';

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

  test('projects a RemoteTarget into a runtime SshProfile', () {
    const endpoint = SshReachabilityEndpoint(
      kind: SshEndpointKind.relay,
      host: 'relay.example.com',
      port: 443,
    );
    const target = RemoteTarget(
      id: 't1',
      name: 'dev',
      host: 'h',
      port: 2222,
      username: 'u',
      authType: SshAuthType.privateKey,
      vaultEntryId: 'vault-1',
      endpoints: [endpoint],
      hostKeyFingerprints: ['SHA256:abc'],
      lastGoodKind: SshEndpointKind.relay,
      lastHome: '/home/u',
      lastAppDataRoot: '/data/u',
      embeddedTarget: true,
      relayUrl: 'wss://relay.example.com',
      pairedDesktopId: 'desktop-1',
      updatedAt: 10,
      pendingSync: true,
    );
    final profile = SshProfile.fromTarget(target);
    expect(profile.id, 't1');
    expect(profile.name, 'dev');
    expect(profile.host, 'h');
    expect(profile.port, 2222);
    expect(profile.username, 'u');
    expect(profile.authType, SshAuthType.privateKey);
    expect(profile.createdAt, 10);
    expect(profile.updatedAt, 10);
    expect(profile.vaultEntryId, 'vault-1');
    expect(profile.endpoints, [endpoint]);
    expect(profile.hostKeyFingerprints, ['SHA256:abc']);
    expect(profile.lastGoodKind, SshEndpointKind.relay);
    expect(profile.lastHome, '/home/u');
    expect(profile.lastAppDataRoot, '/data/u');
    expect(profile.embeddedTarget, isTrue);
    expect(profile.relayUrl, 'wss://relay.example.com');
    expect(profile.pairedDesktopId, 'desktop-1');
  });

  test('facade delegates to an explicit RemoteTargetRepository', () async {
    final (repo, targetRepo) = _facadePair();

    expect(identical(repo.targetRepo, targetRepo), isTrue);

    await repo.save(
      const SshProfile(
        id: 'p1',
        name: 'dev',
        host: 'h',
        username: 'u',
        embeddedTarget: true,
      ),
    );

    final targets = await targetRepo.loadAll();
    expect(targets, hasLength(1));
    expect(targets.single.id, 'p1');
    expect(targets.single.embeddedTarget, isTrue);
    expect(targets.single.pendingSync, isTrue);
    expect(targets.single.updatedAt, greaterThan(0));

    final profiles = await repo.loadAll();
    expect(profiles.single.id, 'p1');
    expect(profiles.single.embeddedTarget, isTrue);
  });

  test(
    'facade save clears nullable fields when updating an existing target',
    () async {
      final (repo, targetRepo) = _facadePair();

      await targetRepo.save(
        const RemoteTarget(
          id: 'p1',
          name: 'dev',
          host: 'h',
          username: 'u',
          vaultEntryId: 'vault-1',
          relayUrl: 'wss://old',
          pairedDesktopId: 'desktop-1',
          lastHome: '/old/home',
          lastAppDataRoot: '/old/data',
          lastGoodKind: SshEndpointKind.relay,
        ),
      );

      await repo.save(
        const SshProfile(id: 'p1', name: 'dev2', host: 'h2', username: 'u2'),
      );

      final target = (await targetRepo.loadAll()).single;
      expect(target.name, 'dev2');
      expect(target.vaultEntryId, isNull);
      expect(target.relayUrl, isNull);
      expect(target.pairedDesktopId, isNull);
      expect(target.lastHome, isNull);
      expect(target.lastAppDataRoot, isNull);
      expect(target.lastGoodKind, isNull);
      expect(target.pendingSync, isTrue);
      expect(target.updatedAt, greaterThan(0));

      final profile = (await repo.loadAll()).single;
      expect(profile.vaultEntryId, isNull);
      expect(profile.relayUrl, isNull);
      expect(profile.lastGoodKind, isNull);
    },
  );

  test(
    'facade saveAll, findById and delete delegate to the target repo',
    () async {
      final (repo, targetRepo) = _facadePair();

      await repo.saveAll(const [
        SshProfile(id: 'a', name: 'A', host: 'ha', username: 'ua'),
        SshProfile(id: 'b', name: 'B', host: 'hb', username: 'ub'),
      ]);
      expect(await targetRepo.loadAll(), hasLength(2));

      final found = await repo.findById('a');
      expect(found?.name, 'A');
      expect(await repo.findById('missing'), isNull);

      await repo.delete('a');
      expect(await targetRepo.loadAll(), hasLength(1));
      expect(await repo.findById('a'), isNull);
      expect((await repo.loadAll()).single.id, 'b');
    },
  );

  test('legacy repo getter throws a clear StateError', () async {
    final repo = SshProfileRepository(storage: fakeHomeStorage());

    // Legacy profiles.json behavior is still intact.
    await repo.save(
      const SshProfile(id: 'p1', name: 'dev', host: 'h', username: 'u'),
    );
    expect(await repo.loadAll(), hasLength(1));

    expect(
      () => repo.targetRepo,
      throwsA(
        predicate<Object>(
          (error) =>
              error is StateError &&
              error.message.contains('RemoteTargetRepository'),
        ),
      ),
    );
  });
}

(SshProfileRepository, RemoteTargetRepository) _facadePair() {
  final fs = InMemoryFilesystem();
  final targetRepo = RemoteTargetRepository(
    rootDir: '/tp/ssh_profiles',
    fs: fs,
  );
  final repo = SshProfileRepository(
    targetRepo: targetRepo,
    storage: fakeHomeStorage(filesystem: fs),
  );
  return (repo, targetRepo);
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
