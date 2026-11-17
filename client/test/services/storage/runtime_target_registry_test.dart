import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';
import 'package:teampilot/services/storage/targets_repository.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  late Directory tmp;
  late TargetsRepository targetsRepo;
  late SshProfileRepository sshRepo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rt_registry_');
    final fs = LocalFilesystem();
    targetsRepo = TargetsRepository(rootDir: tmp.path, fs: fs);
    sshRepo = SshProfileRepository(
      rootDir: tmp.path,
      fs: fs,
      storage: fakeHomeStorage(),
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  RuntimeTargetRegistry build({
    bool isWindows = false,
    bool isAndroid = false,
    bool Function()? hasTermuxConfig,
  }) => RuntimeTargetRegistry(
    repo: targetsRepo,
    sshProfileRepo: sshRepo,
    isWindows: isWindows,
    isAndroid: isAndroid,
    hasTermuxConfig: hasTermuxConfig,
  );

  SshProfile profile(String id) =>
      SshProfile(id: id, name: 'name-$id', host: 'h', username: 'u');

  test('listTargets always includes implicit local first', () async {
    final reg = build();
    final targets = await reg.listTargets();
    expect(targets.first.id, 'local');
  });

  test(
    'listTargets injects implicit wsl on Windows when distro given',
    () async {
      final reg = build(isWindows: true);
      final ids = (await reg.listTargets(wslDistro: 'Ubuntu')).map((t) => t.id);
      expect(ids, contains('wsl:Ubuntu'));
    },
  );

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
    final persisted = (await targetsRepo.load()).targets
        .map((t) => t.id)
        .toSet();
    expect(persisted, {'ssh:p1', 'ssh:p2'});
  });

  test('listTargets injects termux on Android when configured', () async {
    final reg = build(isAndroid: true, hasTermuxConfig: () => true);
    final ids = (await reg.listTargets()).map((t) => t.id).toList();
    expect(ids, contains('termux:default'));
    expect(ids.indexOf('termux:default'), greaterThan(ids.indexOf('local')));
  });

  test('listTargets omits termux on Android when not configured', () async {
    final reg = build(isAndroid: true, hasTermuxConfig: () => false);
    final ids = (await reg.listTargets()).map((t) => t.id);
    expect(ids, isNot(contains('termux:default')));
  });

  test('listTargets omits termux off Android even when configured', () async {
    final reg = build(isAndroid: false, hasTermuxConfig: () => true);
    final ids = (await reg.listTargets()).map((t) => t.id);
    expect(ids, isNot(contains('termux:default')));
  });

  test('read-only palette (repo == null) derives ssh from profiles and never '
      'writes targets.json', () async {
    // A stale persisted target that the read-only palette must ignore.
    await targetsRepo.save(
      TargetsRegistryFile(
        targets: [RuntimeTarget.ssh('stale', label: 'stale')],
      ),
    );
    await sshRepo.saveAll([profile('a')]);
    final reg = RuntimeTargetRegistry(
      // no repo: home-target palette (A source), read-only.
      sshProfileRepo: sshRepo,
      isWindows: false,
      isAndroid: false,
    );
    final ids = (await reg.listTargets()).map((t) => t.id).toSet();
    expect(ids, contains('ssh:a')); // derived straight from the live profiles
    expect(ids, isNot(contains('ssh:stale'))); // persisted file is ignored
    // Persistence is untouched: the palette never reads or writes it.
    final persisted = (await targetsRepo.load()).targets.map((t) => t.id);
    expect(persisted, ['ssh:stale']);
  });

  test('empty workload catalog keeps persisted targets verbatim (offline '
      'guard)', () async {
    await targetsRepo.save(
      TargetsRegistryFile(
        targets: [
          RuntimeTarget.ssh('p1', label: 'one'),
          RuntimeTarget.ssh('p2', label: 'two'),
        ],
      ),
    );
    // sshRepo stays empty: simulates an unreachable / empty B source.
    final reg = build();
    final ids = (await reg.listTargets()).map((t) => t.id).toSet();
    expect(ids, containsAll(['local', 'ssh:p1', 'ssh:p2']));
    // Persisted targets must NOT be pruned and NOT rewritten.
    final persisted =
        (await targetsRepo.load()).targets.map((t) => t.id).toSet();
    expect(persisted, {'ssh:p1', 'ssh:p2'});
  });
}
