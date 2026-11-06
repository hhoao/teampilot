import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/remote_target_repository.dart';
import 'package:teampilot/services/storage/remote_target_migration.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('migrates legacy profiles into remote targets once', () async {
    final fs = InMemoryFilesystem();
    const root = '/tp';
    final legacyFile =
        fs.pathContext.join(root, 'ssh_profiles', 'profiles.json');
    await fs.ensureDir(fs.pathContext.dirname(legacyFile));
    await fs.atomicWrite(
      legacyFile,
      jsonEncode([
        const SshProfile(
          id: 'p1',
          name: 'dev',
          host: 'h',
          username: 'u',
        ).toJson(),
      ]),
    );
    final targetRepo = RemoteTargetRepository(rootDir: root, fs: fs);

    final first = await migrateSshProfiles(
      nativeAppDataPath: root,
      localFs: fs,
      targetRepo: targetRepo,
    );
    expect(first.migrated, 1);
    expect(first.skipped, isFalse);
    expect((await targetRepo.loadAll()).single.id, 'p1');

    final second = await migrateSshProfiles(
      nativeAppDataPath: root,
      localFs: fs,
      targetRepo: targetRepo,
    );
    expect(second.migrated, 0);
    expect(second.skipped, isTrue);
  });
}
