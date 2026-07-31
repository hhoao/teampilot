import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/remote_download/remote_download_catalog.dart';
import 'package:teampilot/services/remote_download/remote_download_settings_store.dart';
import 'package:teampilot/services/remote_download/remote_download_source.dart';
import 'package:teampilot/services/storage/app_storage.dart';

void main() {
  group('RemoteDownloadSettingsStore', () {
    late Directory rootDir;
    late RemoteDownloadSettingsStore store;

    setUp(() async {
      rootDir = await Directory.systemTemp.createTemp('remote_dl_cfg_');
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

    test('loadEffectiveCatalog returns defaults when no file', () async {
      final catalog = await store.loadEffectiveCatalog();

      expect(catalog, RemoteDownloadCatalog.defaults());
    });

    test('round-trips mirrorBaseUrl and source overrides', () async {
      const override = RemoteDownloadSource(
        id: 'github-official',
        priority: 10,
        enabled: false,
        matchHosts: ['github.com', 'api.github.com'],
      );

      await store.save(
        const RemoteDownloadSettings(
          sources: [override],
          mirrorBaseUrl: 'https://mirror.example',
        ),
      );

      final loaded = await store.load();
      expect(loaded, isNotNull);
      expect(loaded!.mirrorBaseUrl, 'https://mirror.example');
      expect(loaded.sources, [override]);
    });

    test('loadEffectiveCatalog merges overrides into defaults', () async {
      await store.save(
        const RemoteDownloadSettings(
          sources: [
            RemoteDownloadSource(
              id: 'github-official',
              priority: 10,
              enabled: false,
              matchHosts: ['github.com', 'api.github.com'],
            ),
          ],
        ),
      );

      final catalog = await store.loadEffectiveCatalog();
      expect(catalog.sources, hasLength(1));
      expect(catalog.sources.single.enabled, isFalse);
    });

    test('mirrorBaseUrl synthesizes github-mirror when absent', () async {
      await store.save(
        const RemoteDownloadSettings(
          mirrorBaseUrl: 'https://mirror.example/',
        ),
      );

      final catalog = await store.loadEffectiveCatalog();
      expect(catalog.sources, hasLength(2));

      final mirror = catalog.sources
          .where((s) => s.id == RemoteDownloadSettingsStore.githubMirrorId)
          .single;
      expect(mirror.priority, 20);
      expect(mirror.enabled, isTrue);
      expect(mirror.matchHosts, ['github.com', 'api.github.com']);
      expect(mirror.rewriteOrigin, 'https://mirror.example');
    });

    test('does not duplicate github-mirror when explicitly persisted', () async {
      await store.save(
        RemoteDownloadSettings(
          mirrorBaseUrl: 'https://mirror.example',
          sources: [
            RemoteDownloadSource(
              id: RemoteDownloadSettingsStore.githubMirrorId,
              priority: 15,
              enabled: true,
              matchHosts: const ['github.com', 'api.github.com'],
              rewriteOrigin: 'https://custom-mirror.example',
            ),
          ],
        ),
      );

      final catalog = await store.loadEffectiveCatalog();
      final mirrors = catalog.sources
          .where((s) => s.id == RemoteDownloadSettingsStore.githubMirrorId);
      expect(mirrors, hasLength(1));
      expect(mirrors.single.priority, 15);
      expect(mirrors.single.rewriteOrigin, 'https://custom-mirror.example');
    });

    test('appends unknown source ids from persisted json', () async {
      const custom = RemoteDownloadSource(
        id: 'corp-mirror',
        priority: 5,
        enabled: true,
        matchHosts: ['github.com'],
        rewriteOrigin: 'https://corp.example',
      );

      await store.save(
        const RemoteDownloadSettings(sources: [custom]),
      );

      final catalog = await store.loadEffectiveCatalog();
      expect(catalog.sources, hasLength(2));
      expect(catalog.sources.map((s) => s.id), containsAll([
        'github-official',
        'corp-mirror',
      ]));
      expect(
        catalog.sources.where((s) => s.id == 'corp-mirror').single,
        custom,
      );
    });

    test('clear removes persisted settings', () async {
      await store.save(
        const RemoteDownloadSettings(mirrorBaseUrl: 'https://mirror.example'),
      );

      await store.clear();

      expect(await store.load(), isNull);
      expect(
        await store.loadEffectiveCatalog(),
        RemoteDownloadCatalog.defaults(),
      );
    });
  });
}
