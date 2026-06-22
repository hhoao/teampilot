import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/connection_mode.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/windows_storage_backend.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';
import 'package:teampilot/services/storage/targets_repository.dart';

void main() {
  late Directory tmp;
  late TargetsRepository targetsRepo;
  late SshProfileRepository sshRepo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rt_registry_');
    final fs = LocalFilesystem();
    targetsRepo = TargetsRepository(rootDir: tmp.path, fs: fs);
    sshRepo = SshProfileRepository(rootDir: tmp.path, fs: fs);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  RuntimeTargetRegistry build({bool isWindows = false, bool isAndroid = false}) =>
      RuntimeTargetRegistry(
        repo: targetsRepo,
        sshProfileRepo: sshRepo,
        isWindows: isWindows,
        isAndroid: isAndroid,
      );

  SshProfile profile(String id) =>
      SshProfile(id: id, name: 'name-$id', host: 'h', username: 'u');

  test('migration: localPty + native -> default local', () async {
    final reg = build();
    await reg.migrateIfNeeded(
      legacyMode: ConnectionMode.localPty,
      legacyBackend: WindowsStorageBackend.native,
      parsedWslDistro: null,
    );
    expect((await reg.defaultTarget()).id, 'local');
  });

  test('migration: ssh + selected profile -> ssh:<id> and persists target',
      () async {
    await sshRepo.saveAll([profile('p1')]);
    await sshRepo.saveSelectedProfileId('p1');
    final reg = build();
    await reg.migrateIfNeeded(
      legacyMode: ConnectionMode.ssh,
      legacyBackend: WindowsStorageBackend.native,
      parsedWslDistro: null,
    );
    final def = await reg.defaultTarget();
    expect(def.id, 'ssh:p1');
    expect(def.kind, RuntimeKind.ssh);
    expect((await reg.listTargets()).any((t) => t.id == 'ssh:p1'), isTrue);
  });

  test('migration: windows wsl backend -> wsl:<distro>', () async {
    final reg = build(isWindows: true);
    await reg.migrateIfNeeded(
      legacyMode: ConnectionMode.localPty,
      legacyBackend: WindowsStorageBackend.wsl,
      parsedWslDistro: 'Ubuntu',
    );
    expect((await reg.defaultTarget()).id, 'wsl:Ubuntu');
    expect(await reg.wslDistro(), 'Ubuntu');
  });

  test('migration: android with profile -> first ssh target', () async {
    await sshRepo.saveAll([profile('pa')]);
    final reg = build(isAndroid: true);
    await reg.migrateIfNeeded(
      legacyMode: ConnectionMode.localPty,
      legacyBackend: WindowsStorageBackend.native,
      parsedWslDistro: null,
    );
    expect((await reg.defaultTarget()).id, 'ssh:pa');
  });

  test('migrateIfNeeded is a no-op when targets.json exists', () async {
    await targetsRepo.save(
      const TargetsRegistryFile(defaultTargetId: 'local'),
    );
    await sshRepo.saveAll([profile('p1')]);
    await sshRepo.saveSelectedProfileId('p1');
    final reg = build();
    await reg.migrateIfNeeded(
      legacyMode: ConnectionMode.ssh,
      legacyBackend: WindowsStorageBackend.native,
      parsedWslDistro: null,
    );
    // existing file wins → stays local
    expect((await targetsRepo.load()).defaultTargetId, 'local');
  });

  test('listTargets always includes implicit local', () async {
    final reg = build();
    expect((await reg.listTargets()).any((t) => t.id == 'local'), isTrue);
  });

  test('reconcile: new ssh profile appears; deleted profile pruned', () async {
    await targetsRepo.save(
      TargetsRegistryFile(
        targets: [
          RuntimeTarget.ssh('p1', label: 'old'),
          RuntimeTarget.ssh('p3', label: 'gone'),
        ],
      ),
    );
    await sshRepo.saveAll([profile('p1'), profile('p2')]);
    final reg = build();
    final ids = (await reg.listTargets()).map((t) => t.id).toSet();
    expect(ids.contains('ssh:p1'), isTrue);
    expect(ids.contains('ssh:p2'), isTrue); // newly added & written back
    expect(ids.contains('ssh:p3'), isFalse); // orphan pruned
    // change persisted back to disk
    final persisted = (await targetsRepo.load()).targets.map((t) => t.id).toSet();
    expect(persisted, {'ssh:p1', 'ssh:p2'});
  });

  test('defaultTarget falls back to local when id points at deleted profile',
      () async {
    await targetsRepo.save(
      const TargetsRegistryFile(defaultTargetId: 'ssh:gone'),
    );
    final reg = build();
    expect((await reg.defaultTarget()).id, 'local');
  });
}
