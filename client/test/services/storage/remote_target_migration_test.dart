import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/remote_target_repository.dart';
import 'package:teampilot/services/ssh/ssh_transport_close.dart';
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

  test('keeps legacy file and retries when legacy catalog is unreadable',
      () async {
    final fs = InMemoryFilesystem();
    const root = '/tp';
    final legacyFile =
        fs.pathContext.join(root, 'ssh_profiles', 'profiles.json');
    final marker = fs.pathContext.join(root, '.remote-targets-migrated.v1');
    await fs.atomicWrite(legacyFile, '{not json');
    final targetRepo = RemoteTargetRepository(rootDir: root, fs: fs);

    final failed = await migrateSshProfiles(
      nativeAppDataPath: root,
      localFs: fs,
      targetRepo: targetRepo,
    );
    expect(failed.migrated, 0);
    expect(failed.skipped, isFalse);
    expect(await fs.readString(legacyFile), '{not json');
    expect((await fs.stat(marker)).exists, isFalse);
    expect(await targetRepo.loadAll(), isEmpty);

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
    final retried = await migrateSshProfiles(
      nativeAppDataPath: root,
      localFs: fs,
      targetRepo: targetRepo,
    );
    expect(retried.migrated, 1);
    expect(retried.skipped, isFalse);
    expect((await targetRepo.loadAll()).single.id, 'p1');
    expect((await fs.stat(marker)).exists, isTrue);
  });

  test('rethrows transport failures instead of reporting no legacy profiles',
      () async {
    // isStorageTransportFailure is partly message-based (storage_failure.dart),
    // so a dropped channel can surface as a FormatException — exactly the type
    // the narrowed parse catch handles. Both shapes must propagate, and the
    // transport guard must take precedence over parse-error handling.
    final transportErrors = <Exception>[
      const SshTransportClosed(
        reason: SshTransportCloseReason.transportError,
        plane: SshTransportPlane.storage,
      ),
      const FormatException('sftp channel closed'),
    ];
    for (final error in transportErrors) {
      final fs = _ReadFailingFilesystem(error);
      const root = '/tp';
      final legacyFile =
          fs.pathContext.join(root, 'ssh_profiles', 'profiles.json');
      final marker = fs.pathContext.join(root, '.remote-targets-migrated.v1');
      await fs.atomicWrite(legacyFile, '[]');
      await expectLater(
        migrateSshProfiles(
          nativeAppDataPath: root,
          localFs: fs,
          targetRepo: RemoteTargetRepository(rootDir: root, fs: fs),
        ),
        throwsA(same(error)),
      );
      expect((await fs.stat(marker)).exists, isFalse);
    }
  });
}

/// Filesystem whose reads fail the way a closed dartssh2 channel does.
class _ReadFailingFilesystem extends InMemoryFilesystem {
  _ReadFailingFilesystem(this._error);

  final Exception _error;

  @override
  Future<String?> readString(String path) async => throw _error;
}
