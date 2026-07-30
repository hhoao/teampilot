import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/termux/termux_config.dart';
import 'package:teampilot/services/termux/termux_config_store.dart';
import '../../support/test_runtime_context.dart';

void main() {
  group('TermuxConfig', () {
    test('json round-trip includes optional paths', () {
      const config = TermuxConfig(
        username: 'u0_a123',
        host: '127.0.0.1',
        port: 8022,
        lastHome: '/data/data/com.termux/files/home',
        lastAppDataRoot: '/data/data/com.termux/files/home/.teampilot',
      );

      final restored = TermuxConfig.fromJson(config.toJson());

      expect(restored.username, 'u0_a123');
      expect(restored.host, '127.0.0.1');
      expect(restored.port, 8022);
      expect(restored.lastHome, '/data/data/com.termux/files/home');
      expect(
        restored.lastAppDataRoot,
        '/data/data/com.termux/files/home/.teampilot',
      );
    });

    test('defaults host and port when omitted from json', () {
      final config = TermuxConfig.fromJson({
        'username': 'u0_a456',
      });

      expect(config.host, '127.0.0.1');
      expect(config.port, 8022);
    });
  });

  group('TermuxConfigStore', () {
    test('round-trips username and port', () async {
      final native = await Directory.systemTemp.createTemp('termux_cfg_');
      addTearDown(() async {
        if (await native.exists()) await native.delete(recursive: true);
      });

      final store = TermuxConfigStore(
        rootDir: native.path,
        fs: LocalFilesystem(
          pathContext: AppPaths.pathContextForDataRoot(native.path),
        ),
      );

      expect(await store.load(), isNull);

      const config = TermuxConfig(username: 'u0_a789', port: 8022);
      await store.save(config);

      final loaded = await store.load();
      expect(loaded, isNotNull);
      expect(loaded!.username, 'u0_a789');
      expect(loaded.port, 8022);
      expect(loaded.host, '127.0.0.1');
    });

    test('survives AppStorage rebind to empty home', () async {
      final native = await Directory.systemTemp.createTemp('termux_native_');
      final remote = await Directory.systemTemp.createTemp('termux_remote_');
      addTearDown(() async {
        if (await native.exists()) await native.delete(recursive: true);
        if (await remote.exists()) await remote.delete(recursive: true);
        AppStorage.resetForTesting();
        AppPathsBootstrapper.resetForTesting();
      });

      bindTestNativeHome(native.path);

      final store = TermuxConfigStore(
        rootDir: native.path,
        fs: LocalFilesystem(
          pathContext: AppPaths.pathContextForDataRoot(native.path),
        ),
      );
      await store.save(
        const TermuxConfig(
          username: 'u0_a999',
          lastHome: '/home',
          lastAppDataRoot: '/home/.teampilot',
        ),
      );

      bindTestNativeHome(remote.path);

      final loaded = await store.load();
      expect(loaded, isNotNull);
      expect(loaded!.username, 'u0_a999');
      expect(loaded.lastHome, '/home');
      expect(loaded.lastAppDataRoot, '/home/.teampilot');
    });

    test('clear removes persisted config', () async {
      final native = await Directory.systemTemp.createTemp('termux_clr_');
      addTearDown(() async {
        if (await native.exists()) await native.delete(recursive: true);
      });

      final store = TermuxConfigStore(
        rootDir: native.path,
        fs: LocalFilesystem(
          pathContext: AppPaths.pathContextForDataRoot(native.path),
        ),
      );
      await store.save(const TermuxConfig(username: 'u0_a111'));
      await store.clear();

      expect(await store.load(), isNull);
    });
  });
}
