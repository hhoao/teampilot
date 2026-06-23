import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/targets_repository.dart';

void main() {
  test('missing file loads empty catalog', () async {
    final tmp = await Directory.systemTemp.createTemp('targets_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = TargetsRepository(rootDir: tmp.path, fs: LocalFilesystem());

    expect(await repo.exists(), isFalse);
    final loaded = await repo.load();
    expect(loaded.targets, isEmpty);
    expect(loaded.schemaVersion, 1);
  });

  test('save then load round-trips the catalog', () async {
    final tmp = await Directory.systemTemp.createTemp('targets_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = TargetsRepository(rootDir: tmp.path, fs: LocalFilesystem());

    await repo.save(
      TargetsRegistryFile(targets: [RuntimeTarget.ssh('p1', label: 'box')]),
    );
    expect(await repo.exists(), isTrue);
    final loaded = await repo.load();
    expect(loaded.targets.single.id, 'ssh:p1');
    expect(loaded.targets.single.kind, RuntimeKind.ssh);
  });

  test('toJson is catalog-only (no defaultTargetId / wslDistro)', () {
    final json = const TargetsRegistryFile().toJson();
    expect(json.keys, containsAll(['schemaVersion', 'targets']));
    expect(json.containsKey('defaultTargetId'), isFalse);
    expect(json.containsKey('wslDistro'), isFalse);
  });
}
