import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/windows_storage_backend.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';

void main() {
  group('WindowsStorageBackendJson', () {
    test('fromJson maps wsl and defaults to native', () {
      expect(
        WindowsStorageBackendJson.fromJson(WindowsStorageBackend.wsl.name),
        WindowsStorageBackend.wsl,
      );
      expect(WindowsStorageBackendJson.fromJson(null), WindowsStorageBackend.native);
      expect(WindowsStorageBackendJson.fromJson('invalid'), WindowsStorageBackend.native);
    });

    test('toJson round-trips', () {
      for (final backend in WindowsStorageBackend.values) {
        expect(
          WindowsStorageBackendJson.fromJson(backend.toJson()),
          backend,
        );
      }
    });
  });

  test('probeWslAvailable returns false off Windows', () async {
    if (Platform.isWindows) return;
    expect(await RuntimeStorageContext.probeWslAvailable(), isFalse);
  });

  test('resolve uses native backend on Windows when requested', () async {
    if (!Platform.isWindows) return;

    final nativeRoot = Directory.systemTemp.createTempSync('teampilot_native_');
    addTearDown(() {
      if (nativeRoot.existsSync()) {
        nativeRoot.deleteSync(recursive: true);
      }
      RuntimeStorageContext.resetForTesting();
      AppPathsBootstrapper.resetForTesting();
    });

    final ctx = await RuntimeStorageContext.resolve(
      isSshMode: false,
      nativeAppDataPath: nativeRoot.path,
      windowsStorageBackend: WindowsStorageBackend.native,
    );

    expect(ctx.mode, StorageBackendMode.native);
    expect(ctx.appDataRoot, nativeRoot.path);
  });
}
