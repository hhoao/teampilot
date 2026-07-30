import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/termux_cubit.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/termux/termux_config.dart';
import 'package:teampilot/services/termux/termux_config_store.dart';
import 'package:teampilot/services/termux/termux_key_material.dart';

void main() {
  group('TermuxCubit', () {
    late Directory nativeDir;
    late TermuxConfigStore store;
    late InMemorySshCredentialStore credentials;
    late List<String> homeSelections;
    late SshProfile? testedProfile;

    TermuxCubit createCubit({
      TermuxConnectTester? testConnect,
      TermuxPathsResolver? resolvePathsAfterHomeSelect,
    }) {
      return TermuxCubit(
        store: store,
        credentials: credentials,
        nativeAppDataPath: nativeDir.path,
        selectHome: (id) async => homeSelections.add(id),
        testConnect:
            testConnect ??
            (profile) async {
              testedProfile = profile;
              return (ok: true, message: '');
            },
        resolvePathsAfterHomeSelect: resolvePathsAfterHomeSelect,
      );
    }

    setUp(() async {
      nativeDir = await Directory.systemTemp.createTemp('termux_cubit_');
      store = TermuxConfigStore(
        rootDir: nativeDir.path,
        fs: LocalFilesystem(
          pathContext: AppPaths.pathContextForDataRoot(nativeDir.path),
        ),
      );
      credentials = InMemorySshCredentialStore();
      homeSelections = [];
      testedProfile = null;
    });

    tearDown(() async {
      if (await nativeDir.exists()) {
        await nativeDir.delete(recursive: true);
      }
    });

    test('connect success marks connected and selects home once', () async {
      const config = TermuxConfig(username: 'u0_a123');
      await store.save(config);

      final cubit = createCubit();
      addTearDown(cubit.close);
      await cubit.hydrate();

      await cubit.connect();

      expect(cubit.state.connected, isTrue);
      expect(cubit.state.config, config);
      expect(cubit.state.lastError, isNull);
      expect(homeSelections, [RuntimeTarget.termuxDefaultId]);
      expect(testedProfile?.id, 'termux');
      expect(testedProfile?.username, 'u0_a123');
    });

    test('connect failure stays disconnected and does not select home', () async {
      const config = TermuxConfig(username: 'u0_a456');
      await store.save(config);

      final cubit = createCubit(
        testConnect: (_) async => (ok: false, message: 'port refused'),
      );
      addTearDown(cubit.close);
      await cubit.hydrate();

      await cubit.connect();

      expect(cubit.state.connected, isFalse);
      expect(cubit.state.config, config);
      expect(cubit.state.lastError, 'port refused');
      expect(homeSelections, isEmpty);
    });

    test('disconnect keeps config and does not change home', () async {
      const config = TermuxConfig(username: 'u0_a789');
      await store.save(config);

      final cubit = createCubit();
      addTearDown(cubit.close);
      await cubit.hydrate();
      await cubit.connect();
      homeSelections.clear();

      await cubit.disconnect();

      expect(cubit.state.connected, isFalse);
      expect(cubit.state.config, config);
      expect(homeSelections, isEmpty);
    });

    test('clearSetup wipes config, keys, and selects local home', () async {
      const config = TermuxConfig(username: 'u0_a999');
      await store.save(config);

      final cubit = createCubit();
      addTearDown(cubit.close);
      await cubit.hydrate();
      await cubit.saveConfig(config);
      homeSelections.clear();

      await cubit.clearSetup();

      expect(cubit.state.connected, isFalse);
      expect(cubit.state.config, isNull);
      expect(await store.load(), isNull);
      expect(
        await credentials.loadPrivateKey(TermuxKeyMaterial.credentialProfileId),
        isNull,
      );
      expect(
        await File(TermuxKeyMaterial.privateKeyPath(nativeDir.path)).exists(),
        isFalse,
      );
      expect(
        await File(TermuxKeyMaterial.publicKeyPath(nativeDir.path)).exists(),
        isFalse,
      );
      expect(homeSelections, [RuntimeTarget.localId]);
    });

    test('connect persists resolved termux paths after home select', () async {
      const config = TermuxConfig(username: 'u0_a222');
      await store.save(config);

      final cubit = createCubit(
        resolvePathsAfterHomeSelect: () async => (
          home: '/data/termux/home',
          appDataRoot: '/data/termux/home/.teampilot',
        ),
      );
      addTearDown(cubit.close);
      await cubit.hydrate();

      await cubit.connect();

      final loaded = await store.load();
      expect(loaded?.lastHome, '/data/termux/home');
      expect(loaded?.lastAppDataRoot, '/data/termux/home/.teampilot');
      expect(cubit.state.config?.lastHome, '/data/termux/home');
    });
  });
}
