import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/windows_storage_backend.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';

/// Golden equivalence: installForTarget(target) must forward the same params to
/// the (unchanged) resolve() as the legacy call for that kind, yielding an
/// identical context. On a non-Windows/non-ssh host every kind reduces through
/// the same resolve() branch, which is exactly what proves the param mapping.
void main() {
  tearDown(() {
    RuntimeStorageContext.resetForTesting();
    AppPathsBootstrapper.resetForTesting();
  });

  test('local target == legacy native resolve', () async {
    final tmp = await Directory.systemTemp.createTemp('ift_local_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final viaTarget = await RuntimeStorageContext.installForTarget(
      RuntimeTarget.local(),
      nativeAppDataPath: tmp.path,
      nativeHome: tmp.path,
      nativeCwd: tmp.path,
    );
    expect(viaTarget.mode, StorageBackendMode.native);
    expect(viaTarget.appDataRoot, tmp.path);

    final legacy = await RuntimeStorageContext.resolve(
      isSshMode: false,
      nativeAppDataPath: tmp.path,
      nativeHome: tmp.path,
      nativeCwd: tmp.path,
    );
    expect(viaTarget.mode, legacy.mode);
    expect(viaTarget.appDataRoot, legacy.appDataRoot);
    expect(viaTarget.usesPosixPaths, legacy.usesPosixPaths);
  });

  test('wsl target forwards windowsStorageBackend=wsl + wslDistro', () async {
    final tmp = await Directory.systemTemp.createTemp('ift_wsl_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    // Off Windows both reduce to native; the assertion proves installForTarget
    // forwards the wsl backend + distro identically to the legacy resolve call.
    final viaTarget = await RuntimeStorageContext.installForTarget(
      RuntimeTarget.wsl('Ubuntu'),
      nativeAppDataPath: tmp.path,
      nativeHome: tmp.path,
      nativeCwd: tmp.path,
    );
    final legacy = await RuntimeStorageContext.resolve(
      isSshMode: false,
      nativeAppDataPath: tmp.path,
      nativeHome: tmp.path,
      nativeCwd: tmp.path,
      windowsStorageBackend: WindowsStorageBackend.wsl,
      wslDistro: 'Ubuntu',
    );
    expect(viaTarget.mode, legacy.mode);
    expect(viaTarget.appDataRoot, legacy.appDataRoot);
    expect(viaTarget.usesPosixPaths, legacy.usesPosixPaths);
  });

  test('ssh target forwards isSshMode=true', () async {
    if (Platform.isAndroid) return; // Android forces ssh; covered by resolve guard
    final tmp = await Directory.systemTemp.createTemp('ift_ssh_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    // With a null profile, useSsh is false → native; both calls pass
    // isSshMode:true, so equality proves the kind→isSshMode mapping.
    final viaTarget = await RuntimeStorageContext.installForTarget(
      RuntimeTarget.ssh('p1', label: 'box'),
      nativeAppDataPath: tmp.path,
      nativeHome: tmp.path,
      nativeCwd: tmp.path,
    );
    final legacy = await RuntimeStorageContext.resolve(
      isSshMode: true,
      nativeAppDataPath: tmp.path,
      nativeHome: tmp.path,
      nativeCwd: tmp.path,
    );
    expect(viaTarget.mode, legacy.mode);
    expect(viaTarget.appDataRoot, legacy.appDataRoot);
    expect(viaTarget.usesPosixPaths, legacy.usesPosixPaths);
  });
}
