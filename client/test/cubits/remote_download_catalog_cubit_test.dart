import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/remote_download_catalog_cubit.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/remote_download/remote_download_catalog.dart';
import 'package:teampilot/services/remote_download/remote_download_settings_store.dart';
import 'package:teampilot/services/storage/app_storage.dart';

void main() {
  group('RemoteDownloadCatalogCubit', () {
    late Directory rootDir;
    late RemoteDownloadSettingsStore store;

    setUp(() async {
      rootDir = await Directory.systemTemp.createTemp('remote_dl_cubit_');
      store = RemoteDownloadSettingsStore(
        rootDir: rootDir.path,
        fs: LocalFilesystem(
          pathContext: AppPaths.pathContextForDataRoot(rootDir.path),
        ),
      );
    });

    tearDown(() async {
      if (await rootDir.exists()) {
        await rootDir.delete(recursive: true);
      }
    });

    RemoteDownloadCatalogCubit createCubit() =>
        RemoteDownloadCatalogCubit(store: store);

    test('initial state is unloaded defaults', () {
      final cubit = createCubit();
      addTearDown(cubit.close);

      expect(cubit.state.loaded, isFalse);
      expect(cubit.state.catalog, RemoteDownloadCatalog.defaults());
      expect(cubit.state.mirrorBaseUrl, isNull);
    });

    test('load emits effective catalog from disk', () async {
      await store.save(
        const RemoteDownloadSettings(mirrorBaseUrl: 'https://mirror.example'),
      );

      final cubit = createCubit();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.loaded, isTrue);
      expect(cubit.state.mirrorBaseUrl, 'https://mirror.example');
      expect(
        cubit.catalog.sources
            .any((s) => s.id == RemoteDownloadSettingsStore.githubMirrorId),
        isTrue,
      );
    });

    test('setMirrorBaseUrl persists and emits mirror source', () async {
      final cubit = createCubit();
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.setMirrorBaseUrl('https://mirror.example/');

      expect(cubit.state.mirrorBaseUrl, 'https://mirror.example/');
      final mirror = cubit.catalog.sources
          .where((s) => s.id == RemoteDownloadSettingsStore.githubMirrorId)
          .single;
      expect(mirror.rewriteOrigin, 'https://mirror.example');

      final settings = await store.load();
      expect(settings?.mirrorBaseUrl, 'https://mirror.example/');
    });

    test('setMirrorBaseUrl null clears mirror', () async {
      await store.save(
        const RemoteDownloadSettings(mirrorBaseUrl: 'https://mirror.example'),
      );

      final cubit = createCubit();
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.setMirrorBaseUrl(null);

      expect(cubit.state.mirrorBaseUrl, isNull);
      expect(
        cubit.catalog.sources
            .any((s) => s.id == RemoteDownloadSettingsStore.githubMirrorId),
        isFalse,
      );
      expect((await store.load())?.mirrorBaseUrl, isNull);
    });

    test('restoreDefaults clears persisted settings', () async {
      await store.save(
        const RemoteDownloadSettings(mirrorBaseUrl: 'https://mirror.example'),
      );

      final cubit = createCubit();
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.restoreDefaults();

      expect(cubit.state.loaded, isTrue);
      expect(cubit.state.mirrorBaseUrl, isNull);
      expect(cubit.state.catalog, RemoteDownloadCatalog.defaults());
      expect(await store.load(), isNull);
    });
  });
}
