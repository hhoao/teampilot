import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/services/remote_download/remote_download_catalog.dart';
import 'package:teampilot/services/remote_download/remote_download_http.dart';
import 'package:teampilot/services/remote_download/remote_download_resolver.dart';
import 'package:teampilot/services/remote_download/remote_downloader.dart';
import 'package:teampilot/services/termux/termux_apk_acquisition.dart';

void main() {
  const releaseJson = {
    'tag_name': 'v0.118.1',
    'assets': [
      {
        'name': 'termux-app_v0.118.1+github-debug_arm64-v8a-debug_signed.apk',
        'browser_download_url':
            'https://github.com/termux/termux-app/releases/download/v0.118.1/termux-app_v0.118.1+github-debug_arm64-v8a-debug_signed.apk',
        'size': 95_000_000,
      },
      {
        'name': 'termux-app_v0.118.1+github-debug_armeabi-v7a-debug_signed.apk',
        'browser_download_url':
            'https://github.com/termux/termux-app/releases/download/v0.118.1/termux-app_v0.118.1+github-debug_armeabi-v7a-debug_signed.apk',
        'size': 90_000_000,
      },
    ],
  };

  late http.Client client;
  late RemoteDownloadHttp downloadHttp;
  late RemoteDownloader downloader;

  setUp(() {
    client = MockClient((request) async {
      if (request.url.path.endsWith('/releases/latest')) {
        return http.Response(jsonEncode(releaseJson), 200);
      }
      return http.Response('not found', 404);
    });
    final resolver = RemoteDownloadResolver(RemoteDownloadCatalog.defaults());
    downloadHttp = RemoteDownloadHttp(client: client, resolver: resolver);
    downloader = RemoteDownloader(client: client, resolver: resolver);
  });

  tearDown(() => client.close());

  group('TermuxApkAcquisition.downloadAndInstall', () {
    test('downloads selected APK and installs it', () async {
      final bytes = List<int>.generate(128, (i) => i % 256);
      client = MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(jsonEncode(releaseJson), 200);
        }
        return http.Response.bytes(bytes, 200);
      });
      final resolver = RemoteDownloadResolver(RemoteDownloadCatalog.defaults());
      downloadHttp = RemoteDownloadHttp(client: client, resolver: resolver);
      downloader = RemoteDownloader(client: client, resolver: resolver);

      String? installedPath;
      final acquisition = TermuxApkAcquisition(
        http: downloadHttp,
        downloader: downloader,
        installApk: (apkPath) async {
          installedPath = apkPath;
          return 0;
        },
      );

      final result = await acquisition.downloadAndInstall(preferArm64: true);
      addTearDown(() async {
        final parent = Directory(result.apkFile?.parent.path ?? '');
        if (await parent.exists()) {
          await parent.delete(recursive: true);
        }
      });

      expect(result.success, isTrue);
      expect(result.assetName, contains('arm64-v8a'));
      expect(result.installStatusCode, 0);
      expect(installedPath, isNotNull);
      expect(File(installedPath!).lengthSync(), bytes.length);
    });

    test('reports API failure', () async {
      client = MockClient((_) async => http.Response('rate limit', 403));
      final resolver = RemoteDownloadResolver(RemoteDownloadCatalog.defaults());
      downloadHttp = RemoteDownloadHttp(client: client, resolver: resolver);
      downloader = RemoteDownloader(client: client, resolver: resolver);

      final acquisition = TermuxApkAcquisition(
        http: downloadHttp,
        downloader: downloader,
        installApk: (_) async => 0,
      );

      final result = await acquisition.downloadAndInstall(preferArm64: true);
      expect(result.success, isFalse);
      expect(result.phase, TermuxApkAcquirePhase.apiFailed);
      expect(result.errorMessage, isNotEmpty);
    });

    test('reports asset-not-found when release has no APK', () async {
      client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'tag_name': 'v0.118.1',
            'assets': [
              {
                'name': 'checksums.txt',
                'browser_download_url': 'https://example.com/checksums.txt',
                'size': 1,
              },
            ],
          }),
          200,
        ),
      );
      final resolver = RemoteDownloadResolver(RemoteDownloadCatalog.defaults());
      downloadHttp = RemoteDownloadHttp(client: client, resolver: resolver);
      downloader = RemoteDownloader(client: client, resolver: resolver);

      final acquisition = TermuxApkAcquisition(
        http: downloadHttp,
        downloader: downloader,
        installApk: (_) async => 0,
      );

      final result = await acquisition.downloadAndInstall(preferArm64: true);
      expect(result.success, isFalse);
      expect(result.phase, TermuxApkAcquirePhase.assetNotFound);
    });

    test('reports install failure when installer returns non-success', () async {
      final bytes = List<int>.generate(64, (i) => i);
      client = MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(jsonEncode(releaseJson), 200);
        }
        return http.Response.bytes(bytes, 200);
      });
      final resolver = RemoteDownloadResolver(RemoteDownloadCatalog.defaults());
      downloadHttp = RemoteDownloadHttp(client: client, resolver: resolver);
      downloader = RemoteDownloader(client: client, resolver: resolver);

      final acquisition = TermuxApkAcquisition(
        http: downloadHttp,
        downloader: downloader,
        installApk: (_) async => 3,
      );

      final result = await acquisition.downloadAndInstall(preferArm64: true);
      addTearDown(() async {
        final parent = Directory(result.apkFile?.parent.path ?? '');
        if (await parent.exists()) {
          await parent.delete(recursive: true);
        }
      });

      expect(result.success, isFalse);
      expect(result.phase, TermuxApkAcquirePhase.installFailed);
      expect(result.installStatusCode, 3);
    });

    test('forwards download progress callbacks', () async {
      final bytes = List<int>.generate(256, (i) => i % 256);
      client = MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(jsonEncode(releaseJson), 200);
        }
        return http.Response.bytes(bytes, 200);
      });
      final resolver = RemoteDownloadResolver(RemoteDownloadCatalog.defaults());
      downloadHttp = RemoteDownloadHttp(client: client, resolver: resolver);
      downloader = RemoteDownloader(client: client, resolver: resolver);

      final progress = <int>[];
      final acquisition = TermuxApkAcquisition(
        http: downloadHttp,
        downloader: downloader,
        installApk: (_) async => 0,
      );

      final result = await acquisition.downloadAndInstall(
        preferArm64: true,
        onProgress: (received, total) => progress.add(received),
      );
      addTearDown(() async {
        final parent = Directory(result.apkFile?.parent.path ?? '');
        if (await parent.exists()) {
          await parent.delete(recursive: true);
        }
      });

      expect(progress, isNotEmpty);
      expect(progress.last, bytes.length);
    });
  });
}
