import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/connection_mode.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/windows_storage_backend.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';
import 'package:teampilot/services/storage/targets_repository.dart';

/// P0 acceptance: behavior is unchanged. Two layers:
///  1. installForTarget(target) yields the same context as the legacy
///     resolve(...) call for that kind (the storage mapping is pure forwarding).
///  2. The one-time migration seeds the defaultTargetId that reproduces today's
///     effective backend for each legacy preference combination.
void main() {
  group('installForTarget ≡ legacy resolve (per kind)', () {
    tearDown(() {
      RuntimeStorageContext.resetForTesting();
      AppPathsBootstrapper.resetForTesting();
    });

    Future<void> expectParity(RuntimeTarget target, RuntimeStorageContext legacy,
        Directory tmp) async {
      final viaTarget = await RuntimeStorageContext.installForTarget(
        target,
        nativeAppDataPath: tmp.path,
        nativeHome: tmp.path,
        nativeCwd: tmp.path,
      );
      expect(viaTarget.mode, legacy.mode);
      expect(viaTarget.appDataRoot, legacy.appDataRoot);
      expect(viaTarget.usesPosixPaths, legacy.usesPosixPaths);
    }

    test('local kind', () async {
      final tmp = await Directory.systemTemp.createTemp('p0_parity_local_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final legacy = await RuntimeStorageContext.resolve(
        isSshMode: false,
        nativeAppDataPath: tmp.path,
        nativeHome: tmp.path,
        nativeCwd: tmp.path,
      );
      await expectParity(RuntimeTarget.local(), legacy, tmp);
    });

    test('wsl kind forwards backend + distro', () async {
      final tmp = await Directory.systemTemp.createTemp('p0_parity_wsl_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final legacy = await RuntimeStorageContext.resolve(
        isSshMode: false,
        nativeAppDataPath: tmp.path,
        nativeHome: tmp.path,
        nativeCwd: tmp.path,
        windowsStorageBackend: WindowsStorageBackend.wsl,
        wslDistro: 'Ubuntu',
      );
      await expectParity(RuntimeTarget.wsl('Ubuntu'), legacy, tmp);
    });

    test('ssh kind forwards isSshMode (null profile → native, as today)',
        () async {
      if (Platform.isAndroid) return;
      final tmp = await Directory.systemTemp.createTemp('p0_parity_ssh_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final legacy = await RuntimeStorageContext.resolve(
        isSshMode: true,
        nativeAppDataPath: tmp.path,
        nativeHome: tmp.path,
        nativeCwd: tmp.path,
      );
      await expectParity(RuntimeTarget.ssh('p1', label: 'box'), legacy, tmp);
    });
  });

  group('migration reproduces today\'s effective default per legacy combo', () {
    late Directory tmp;
    late TargetsRepository targetsRepo;
    late SshProfileRepository sshRepo;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('p0_parity_mig_');
      final fs = LocalFilesystem();
      targetsRepo = TargetsRepository(rootDir: tmp.path, fs: fs);
      sshRepo = SshProfileRepository(rootDir: tmp.path, fs: fs);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    RuntimeTargetRegistry build({
      bool isWindows = false,
      bool isAndroid = false,
    }) =>
        RuntimeTargetRegistry(
          repo: targetsRepo,
          sshProfileRepo: sshRepo,
          isWindows: isWindows,
          isAndroid: isAndroid,
        );

    test('localPty + native → local', () async {
      final reg = build();
      await reg.migrateIfNeeded(
        legacyMode: ConnectionMode.localPty,
        legacyBackend: WindowsStorageBackend.native,
        parsedWslDistro: null,
      );
      expect((await reg.defaultTarget()).kind, RuntimeKind.local);
    });

    test('ssh + selected profile → ssh', () async {
      await sshRepo.saveAll(
        [const SshProfile(id: 'p1', name: 'box', host: 'h', username: 'u')],
      );
      await sshRepo.saveSelectedProfileId('p1');
      final reg = build();
      await reg.migrateIfNeeded(
        legacyMode: ConnectionMode.ssh,
        legacyBackend: WindowsStorageBackend.native,
        parsedWslDistro: null,
      );
      expect((await reg.defaultTarget()).id, 'ssh:p1');
    });

    test('windows + wsl backend → wsl', () async {
      final reg = build(isWindows: true);
      await reg.migrateIfNeeded(
        legacyMode: ConnectionMode.localPty,
        legacyBackend: WindowsStorageBackend.wsl,
        parsedWslDistro: 'Ubuntu',
      );
      expect((await reg.defaultTarget()).id, 'wsl:Ubuntu');
    });
  });
}
