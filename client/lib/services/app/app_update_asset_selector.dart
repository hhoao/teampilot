import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import '../../config/app_update_config.dart';

/// Which release binary this install expects (aligned with CI asset names).
enum AppUpdateInstallKind {
  windowsSetup,
  linuxAppImage,
  linuxDeb,
  macosDmg,
  androidApk,
}

/// Resolves the install kind for the running process.
AppUpdateInstallKind resolveAppUpdateInstallKind() {
  if (Platform.isWindows) return AppUpdateInstallKind.windowsSetup;
  if (Platform.isMacOS) return AppUpdateInstallKind.macosDmg;
  if (Platform.isLinux) {
    final appImage = Platform.environment['APPIMAGE'];
    if (appImage != null && appImage.isNotEmpty) {
      return AppUpdateInstallKind.linuxAppImage;
    }
    return AppUpdateInstallKind.linuxDeb;
  }
  if (Platform.isAndroid) return AppUpdateInstallKind.androidApk;
  throw UnsupportedError('In-app updates are not supported on this platform.');
}

/// Android APK ABI suffix used in release filenames (`teampilot-*-arm64-v8a.apk`).
String androidApkAbiSuffix({bool preferArm64 = true}) {
  return preferArm64 ? 'arm64-v8a' : 'armeabi-v7a';
}

/// Extracts a release tag from a GitHub release page or redirect URL.
String? parseReleaseTagFromGithubUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final match = RegExp(r'/releases/tag/([^/?#]+)').firstMatch(uri.path);
  final tag = match?.group(1)?.trim();
  if (tag == null || tag.isEmpty) return null;
  return tag;
}

/// Builds the GitHub `releases/download/{tag}/{asset}` URL for [assetName].
String githubReleaseAssetDownloadUrl({
  required String owner,
  required String repo,
  required String tagName,
  required String assetName,
}) {
  final encodedTag = Uri.encodeComponent(tagName);
  final encodedAsset = Uri.encodeComponent(assetName);
  return 'https://github.com/$owner/$repo/releases/download/$encodedTag/$encodedAsset';
}

/// Expected CI release filename for [version] (inverse of [selectReleaseAssetName]).
String buildExpectedReleaseAssetName({
  required Version version,
  required AppUpdateInstallKind kind,
  String slug = appUpdateReleaseArtifactSlug,
  String androidAbiSuffix = 'arm64-v8a',
}) {
  final v = version.toString();
  return switch (kind) {
    AppUpdateInstallKind.windowsSetup => '$slug-$v-windows-setup.exe',
    AppUpdateInstallKind.linuxAppImage => '$slug-$v-linux.AppImage',
    AppUpdateInstallKind.linuxDeb => '$slug-$v-linux.deb',
    AppUpdateInstallKind.macosDmg => '$slug-$v.dmg',
    AppUpdateInstallKind.androidApk => '$slug-$v-$androidAbiSuffix.apk',
  };
}

/// Strips a leading `v` from a Git tag (`v1.0.1` → `1.0.1`).
String parseReleaseVersionFromTag(String tagName) {
  final trimmed = tagName.trim();
  if (trimmed.isEmpty) return trimmed;
  if (trimmed.startsWith('v') || trimmed.startsWith('V')) {
    return trimmed.substring(1);
  }
  return trimmed;
}

/// Picks the single GitHub release asset name for [kind] from [assetNames].
///
/// Throws [AppUpdateAssetNotFoundException] when no match exists.
String selectReleaseAssetName({
  required Iterable<String> assetNames,
  required AppUpdateInstallKind kind,
  String androidAbiSuffix = 'arm64-v8a',
}) {
  final names = assetNames.toList();
  String? pick(bool Function(String name) test) {
    for (final name in names) {
      if (test(name)) return name;
    }
    return null;
  }

  final lower = names.map((n) => (name: n, low: n.toLowerCase())).toList();

  String? selected = switch (kind) {
    AppUpdateInstallKind.windowsSetup => pick(
      (n) {
        final low = n.toLowerCase();
        return low.endsWith('.exe') && low.contains('-setup');
      },
    ),
    AppUpdateInstallKind.linuxAppImage => pick(
      (n) => n.toLowerCase().endsWith('.appimage'),
    ),
    AppUpdateInstallKind.linuxDeb => pick(
      (n) {
        final low = n.toLowerCase();
        return low.endsWith('.deb') && low.contains('-linux');
      },
    ),
    AppUpdateInstallKind.macosDmg => pick(
      (n) => n.toLowerCase().endsWith('.dmg'),
    ),
    AppUpdateInstallKind.androidApk => () {
      final suffix = '-$androidAbiSuffix.apk'.toLowerCase();
      for (final entry in lower) {
        if (entry.low.endsWith(suffix)) return entry.name;
      }
      return null;
    }(),
  };

  if (selected != null) return selected;

  throw AppUpdateAssetNotFoundException(kind, names);
}

class AppUpdateAssetNotFoundException implements Exception {
  AppUpdateAssetNotFoundException(this.kind, this.availableAssetNames);

  final AppUpdateInstallKind kind;
  final List<String> availableAssetNames;

  @override
  String toString() =>
      'No release asset for $kind (available: ${availableAssetNames.join(', ')})';
}
