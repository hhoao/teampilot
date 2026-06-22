import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/targets_repository.dart';

void main() {
  test('missing file loads empty defaults', () async {
    final tmp = await Directory.systemTemp.createTemp('targets_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = TargetsRepository(rootDir: tmp.path, fs: LocalFilesystem());

    expect(await repo.exists(), isFalse);
    final loaded = await repo.load();
    expect(loaded.defaultTargetId, 'local');
    expect(loaded.targets, isEmpty);
  });

  test('save then load round-trips', () async {
    final tmp = await Directory.systemTemp.createTemp('targets_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = TargetsRepository(rootDir: tmp.path, fs: LocalFilesystem());

    await repo.save(
      TargetsRegistryFile(
        defaultTargetId: 'ssh:p1',
        wslDistro: 'Ubuntu',
        targets: [RuntimeTarget.ssh('p1', label: 'box')],
      ),
    );
    expect(await repo.exists(), isTrue);
    final loaded = await repo.load();
    expect(loaded.defaultTargetId, 'ssh:p1');
    expect(loaded.wslDistro, 'Ubuntu');
    expect(loaded.targets.single.id, 'ssh:p1');
    expect(loaded.targets.single.kind, RuntimeKind.ssh);
  });
}
