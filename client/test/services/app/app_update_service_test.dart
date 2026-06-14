import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:teampilot/models/app_release_info.dart';
import 'package:teampilot/config/app_update_config.dart';
import 'package:teampilot/services/app/app_update_asset_selector.dart';
import 'package:teampilot/services/app/app_update_service.dart';

void main() {
  group('parseReleaseVersionFromTag', () {
    test('strips leading v', () {
      expect(parseReleaseVersionFromTag('v1.2.3'), '1.2.3');
      expect(parseReleaseVersionFromTag('V1.0.0'), '1.0.0');
    });

    test('leaves plain semver', () {
      expect(parseReleaseVersionFromTag('2.0.0'), '2.0.0');
    });
  });

  group('selectReleaseAssetName', () {
    const assets = [
      'teampilot-1.0.0-linux.deb',
      'teampilot-1.0.0-linux.AppImage',
      'teampilot-1.0.0.dmg',
      'teampilot-1.0.0-windows-setup.exe',
      'teampilot-1.0.0-arm64-v8a.apk',
      'teampilot-1.0.0-armeabi-v7a.apk',
    ];

    test('windows setup exe', () {
      expect(
        selectReleaseAssetName(
          assetNames: assets,
          kind: AppUpdateInstallKind.windowsSetup,
        ),
        'teampilot-1.0.0-windows-setup.exe',
      );
    });

    test('linux deb', () {
      expect(
        selectReleaseAssetName(
          assetNames: assets,
          kind: AppUpdateInstallKind.linuxDeb,
        ),
        'teampilot-1.0.0-linux.deb',
      );
    });

    test('linux appimage', () {
      expect(
        selectReleaseAssetName(
          assetNames: assets,
          kind: AppUpdateInstallKind.linuxAppImage,
        ),
        'teampilot-1.0.0-linux.AppImage',
      );
    });

    test('macos dmg', () {
      expect(
        selectReleaseAssetName(
          assetNames: assets,
          kind: AppUpdateInstallKind.macosDmg,
        ),
        'teampilot-1.0.0.dmg',
      );
    });

    test('android arm64 apk', () {
      expect(
        selectReleaseAssetName(
          assetNames: assets,
          kind: AppUpdateInstallKind.androidApk,
          androidAbiSuffix: 'arm64-v8a',
        ),
        'teampilot-1.0.0-arm64-v8a.apk',
      );
    });

    test('android armeabi apk', () {
      expect(
        selectReleaseAssetName(
          assetNames: assets,
          kind: AppUpdateInstallKind.androidApk,
          androidAbiSuffix: 'armeabi-v7a',
        ),
        'teampilot-1.0.0-armeabi-v7a.apk',
      );
    });

    test('throws when no match', () {
      expect(
        () => selectReleaseAssetName(
          assetNames: const ['other.zip'],
          kind: AppUpdateInstallKind.windowsSetup,
        ),
        throwsA(isA<AppUpdateAssetNotFoundException>()),
      );
    });
  });

  group('parseReleaseTagFromGithubUrl', () {
    test('extracts tag from release page URL', () {
      expect(
        parseReleaseTagFromGithubUrl(
          'https://github.com/hhoao/teampilot/releases/tag/v1.2.3',
        ),
        'v1.2.3',
      );
    });
  });

  group('buildExpectedReleaseAssetName', () {
    test('windows setup exe', () {
      expect(
        buildExpectedReleaseAssetName(
          version: Version(1, 2, 3),
          kind: AppUpdateInstallKind.windowsSetup,
        ),
        '$appUpdateReleaseArtifactSlug-1.2.3-windows-setup.exe',
      );
    });
  });

  group('AppUpdateService.checkForUpdates', () {
    late AppUpdateService service;

    const releaseJson = {
      'tag_name': 'v1.1.0',
      'body': '## Changes\n- Fix bugs',
      'html_url': 'https://github.com/hhoao/teampilot/releases/tag/v1.1.0',
      'assets': [
        {
          'name': 'teampilot-1.1.0-windows-setup.exe',
          'browser_download_url': 'https://example.com/setup.exe',
          'size': 1000,
        },
        {
          'name': 'teampilot-1.1.0-linux.deb',
          'browser_download_url': 'https://example.com/pkg.deb',
          'size': 2000,
        },
      ],
    };

    PackageInfo packageInfo(String version) => PackageInfo(
      appName: 'teampilot',
      packageName: 'com.hhoa.teampilot',
      version: version,
      buildNumber: '1',
    );

    setUp(() {
      service = AppUpdateService(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/releases/latest')) {
            return http.Response(jsonEncode(releaseJson), 200);
          }
          return http.Response('not found', 404);
        }),
        packageInfoLoader: () async => packageInfo('1.0.0'),
        installKindResolver: () => AppUpdateInstallKind.windowsSetup,
      );
    });

    tearDown(() => service.dispose());

    test('returns available when remote is newer', () async {
      final result = await service.checkForUpdates();
      expect(result, isA<AppUpdateAvailable>());
      final available = result as AppUpdateAvailable;
      expect(available.release.version, Version(1, 1, 0));
      expect(available.release.assetName, 'teampilot-1.1.0-windows-setup.exe');
      expect(available.release.downloadUrl, 'https://example.com/setup.exe');
    });

    test('returns up to date when current >= release', () async {
      service.dispose();
      service = AppUpdateService(
        httpClient: MockClient(
          (request) async =>
              http.Response(jsonEncode(releaseJson), 200),
        ),
        packageInfoLoader: () async => packageInfo('1.1.0'),
        installKindResolver: () => AppUpdateInstallKind.windowsSetup,
      );
      final result = await service.checkForUpdates();
      expect(result, isA<AppUpdateUpToDate>());
    });

    test('throws on API error', () async {
      service.dispose();
      service = AppUpdateService(
        httpClient: MockClient((_) async => http.Response('rate limit', 403)),
        packageInfoLoader: () async => packageInfo('1.0.0'),
        installKindResolver: () => AppUpdateInstallKind.windowsSetup,
      );
      await expectLater(
        service.checkForUpdates(),
        throwsA(isA<AppUpdateException>()),
      );
    });

    test('falls back when API is rate limited', () async {
      service.dispose();
      service = AppUpdateService(
        httpClient: MockClient((request) async {
          final url = request.url.toString();
          if (url.contains('/releases/latest') &&
              url.contains('api.github.com')) {
            return http.Response('rate limit', 403, headers: {
              'x-ratelimit-remaining': '0',
            });
          }
          if (url.endsWith('/releases/latest')) {
            return http.Response('', 302, headers: {
              'location':
                  'https://github.com/hhoao/teampilot/releases/tag/v1.1.0',
            });
          }
          if (url.contains('/releases/download/v1.1.0/')) {
            return http.Response('', 200, headers: {'content-length': '1000'});
          }
          return http.Response('not found', 404);
        }),
        packageInfoLoader: () async => packageInfo('1.0.0'),
        installKindResolver: () => AppUpdateInstallKind.windowsSetup,
      );

      final result = await service.checkForUpdates();
      expect(result, isA<AppUpdateAvailable>());
      final available = result as AppUpdateAvailable;
      expect(available.release.version, Version(1, 1, 0));
      expect(
        available.release.assetName,
        '$appUpdateReleaseArtifactSlug-1.1.0-windows-setup.exe',
      );
      expect(
        available.release.downloadUrl,
        contains('/releases/download/v1.1.0/'),
      );
    });
  });

  group('AppUpdateService.downloadRelease', () {
    test('writes file and reports progress', () async {
      final bytes = List<int>.generate(256, (i) => i % 256);
      final service = AppUpdateService(
        httpClient: MockClient(
          (_) async => http.Response.bytes(bytes, 200),
        ),
        packageInfoLoader: () async => PackageInfo(
          appName: 'teampilot',
          packageName: 'com.hhoa.teampilot',
          version: '1.0.0',
          buildNumber: '1',
        ),
      );
      addTearDown(service.dispose);

      final release = AppReleaseInfo(
        version: Version(1, 1, 0),
        tagName: 'v1.1.0',
        releaseNotes: '',
        downloadUrl: 'https://example.com/pkg.exe',
        assetName: 'teampilot-1.1.0-windows-setup.exe',
        fileSize: bytes.length,
        htmlUrl: 'https://example.com',
      );

      final progress = <double>[];
      final file = await service.downloadRelease(
        release,
        onProgress: progress.add,
      );
      addTearDown(() async {
        final parent = file.parent;
        if (await parent.exists()) {
          await parent.delete(recursive: true);
        }
      });

      expect(await file.length(), bytes.length);
      expect(progress.isNotEmpty, isTrue);
      expect(progress.last, 1.0);
    });
  });
}
