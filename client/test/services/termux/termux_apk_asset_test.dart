import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/termux/termux_apk_asset.dart';

void main() {
  const fixtureAssets = [
    {
      'name': 'termux-app_v0.118.1+github-debug_universal-debug_signed.apk',
      'browser_download_url':
          'https://github.com/termux/termux-app/releases/download/v0.118.1/termux-app_v0.118.1+github-debug_universal-debug_signed.apk',
      'size': 120_000_000,
    },
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
    {
      'name': 'checksums.txt',
      'browser_download_url':
          'https://github.com/termux/termux-app/releases/download/v0.118.1/checksums.txt',
      'size': 512,
    },
  ];

  group('termuxLatestReleaseApiUri', () {
    test('points at termux-app latest release API', () {
      expect(
        termuxLatestReleaseApiUri(),
        Uri.parse(
          'https://api.github.com/repos/termux/termux-app/releases/latest',
        ),
      );
    });
  });

  group('selectTermuxApkDownloadUrl', () {
    test('prefer arm64 asset from release JSON fixture', () {
      final url = selectTermuxApkDownloadUrl(
        assets: fixtureAssets,
        preferArm64: true,
      );
      expect(url, contains('arm64-v8a'));
      expect(url, isNot(contains('universal')));
    });

    test('preferArm64 false picks armeabi-v7a', () {
      final url = selectTermuxApkDownloadUrl(
        assets: fixtureAssets,
        preferArm64: false,
      );
      expect(url, contains('armeabi-v7a'));
    });

    test('prefers canonical termux-app asset when multiple ABI matches', () {
      final url = selectTermuxApkDownloadUrl(
        assets: [
          {
            'name': 'custom_arm64-v8a.apk',
            'browser_download_url': 'https://example.com/custom.apk',
            'size': 1,
          },
          {
            'name': 'termux-app_v1.0.0_arm64-v8a.apk',
            'browser_download_url': 'https://example.com/canonical.apk',
            'size': 2,
          },
        ],
        preferArm64: true,
      );
      expect(url, 'https://example.com/canonical.apk');
    });

    test('throws when no matching APK asset exists', () {
      expect(
        () => selectTermuxApkDownloadUrl(
          assets: const [
            {
              'name': 'checksums.txt',
              'browser_download_url': 'https://example.com/checksums.txt',
              'size': 1,
            },
          ],
          preferArm64: true,
        ),
        throwsA(isA<TermuxApkAssetNotFoundException>()),
      );
    });

    test('throws when browser_download_url is missing', () {
      expect(
        () => selectTermuxApkDownloadUrl(
          assets: const [
            {
              'name': 'termux-app_v1.0.0_arm64-v8a.apk',
              'size': 1,
            },
          ],
          preferArm64: true,
        ),
        throwsA(isA<TermuxApkAssetNotFoundException>()),
      );
    });
  });

  group('selectTermuxApkAssetName', () {
    test('returns matching asset name for ABI', () {
      expect(
        selectTermuxApkAssetName(assets: fixtureAssets, preferArm64: true),
        contains('arm64-v8a'),
      );
    });
  });
}
