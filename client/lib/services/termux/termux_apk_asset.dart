import '../app/app_update_asset_selector.dart';

/// GitHub REST endpoint for the latest `termux/termux-app` release metadata.
Uri termuxLatestReleaseApiUri() => Uri.parse(
  'https://api.github.com/repos/termux/termux-app/releases/latest',
);

/// Picks the `browser_download_url` for the preferred Termux APK asset.
///
/// Throws [TermuxApkAssetNotFoundException] when no matching asset exists.
String selectTermuxApkDownloadUrl({
  required Iterable<Map<String, dynamic>> assets,
  required bool preferArm64,
}) {
  final assetName = selectTermuxApkAssetName(
    assets: assets,
    preferArm64: preferArm64,
  );
  final url = _assetDownloadUrl(assets, assetName);
  if (url == null || url.isEmpty) {
    throw TermuxApkAssetNotFoundException(
      preferArm64: preferArm64,
      availableAssetNames: _assetNames(assets),
    );
  }
  return url;
}

/// Picks the Termux APK asset filename for the preferred ABI.
///
/// Throws [TermuxApkAssetNotFoundException] when no matching asset exists.
String selectTermuxApkAssetName({
  required Iterable<Map<String, dynamic>> assets,
  required bool preferArm64,
}) {
  final abiSuffix = androidApkAbiSuffix(preferArm64: preferArm64);
  final candidates = <String>[];

  for (final asset in assets) {
    final name = asset['name'] as String? ?? '';
    if (!_isApkAssetForAbi(name, abiSuffix)) continue;
    candidates.add(name);
  }

  if (candidates.isEmpty) {
    throw TermuxApkAssetNotFoundException(
      preferArm64: preferArm64,
      availableAssetNames: _assetNames(assets),
    );
  }

  final canonicalPattern = RegExp(
    '^termux-app_.*_${RegExp.escape(abiSuffix)}.*\\.apk\$',
    caseSensitive: false,
  );
  for (final name in candidates) {
    if (canonicalPattern.hasMatch(name)) {
      return name;
    }
  }

  return candidates.first;
}

bool _isApkAssetForAbi(String name, String abiSuffix) {
  final lower = name.toLowerCase();
  return lower.endsWith('.apk') && lower.contains(abiSuffix.toLowerCase());
}

String? _assetDownloadUrl(
  Iterable<Map<String, dynamic>> assets,
  String assetName,
) {
  for (final asset in assets) {
    if (asset['name'] == assetName) {
      return asset['browser_download_url'] as String?;
    }
  }
  return null;
}

List<String> _assetNames(Iterable<Map<String, dynamic>> assets) {
  return assets
      .map((asset) => asset['name'] as String? ?? '')
      .where((name) => name.isNotEmpty)
      .toList();
}

class TermuxApkAssetNotFoundException implements Exception {
  TermuxApkAssetNotFoundException({
    required this.preferArm64,
    required this.availableAssetNames,
  });

  final bool preferArm64;
  final List<String> availableAssetNames;

  @override
  String toString() {
    final abi = androidApkAbiSuffix(preferArm64: preferArm64);
    return 'No Termux APK asset for $abi '
        '(available: ${availableAssetNames.join(', ')})';
  }
}
