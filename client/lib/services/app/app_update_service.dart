import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import '../../config/app_update_config.dart';
import '../../models/app_release_info.dart';
import 'app_update_asset_selector.dart';

typedef AppUpdateHttpClient = http.Client;
typedef PackageInfoLoader = Future<PackageInfo> Function();

/// Fetches GitHub Releases, selects platform assets, and downloads updates.
class AppUpdateService {
  AppUpdateService({
    http.Client? httpClient,
    PackageInfoLoader? packageInfoLoader,
    AppUpdateInstallKind Function()? installKindResolver,
    String? userAgent,
    String? githubOwner,
    String? githubRepo,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _packageInfoLoader =
           packageInfoLoader ?? (() => PackageInfo.fromPlatform()),
       _installKindResolver =
           installKindResolver ?? resolveAppUpdateInstallKind,
       _userAgent = userAgent,
       _githubOwner = githubOwner,
       _githubRepo = githubRepo;

  final http.Client _httpClient;
  final bool _ownsClient;
  final PackageInfoLoader _packageInfoLoader;
  final AppUpdateInstallKind Function() _installKindResolver;
  final String? _userAgent;
  final String? _githubOwner;
  final String? _githubRepo;

  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }

  Future<Version> currentVersion() async {
    final info = await _packageInfoLoader();
    return Version.parse(info.version);
  }

  Future<String> currentVersionLabel() async {
    final info = await _packageInfoLoader();
    final build = info.buildNumber.trim();
    if (build.isEmpty || build == '0') return info.version;
    return '${info.version}+$build';
  }

  /// Whether this device should prefer the arm64-v8a APK (vs armeabi-v7a).
  static Future<bool> preferArm64AndroidApk() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await Process.run('getprop', ['ro.product.cpu.abi']);
      final abi = '${result.stdout}'.trim().toLowerCase();
      if (abi.contains('armeabi-v7a') && !abi.contains('arm64')) {
        return false;
      }
    } catch (_) {
      // Default to arm64 for modern devices.
    }
    return true;
  }

  /// Compares the running app to `releases/latest` on GitHub.
  Future<AppUpdateCheckResult> checkForUpdates({
    bool? preferAndroidArm64,
  }) async {
    final preferArm64 =
        preferAndroidArm64 ?? await preferArm64AndroidApk();
    final current = await currentVersion();
    final release = await _fetchLatestRelease(
      preferAndroidArm64: preferArm64,
    );
    if (current >= release.version) {
      return AppUpdateUpToDate();
    }
    return AppUpdateAvailable(release);
  }

  Future<AppReleaseInfo> _fetchLatestRelease({
    bool preferAndroidArm64 = true,
  }) async {
    final url = appUpdateLatestReleaseApiUrl(
      owner: _githubOwner,
      repo: _githubRepo,
    );
    final info = await _packageInfoLoader();
    final response = await _httpClient.get(
      Uri.parse(url),
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': _userAgent ?? 'TeamPilot/${info.version}',
      },
    );
    if (response.statusCode != 200) {
      throw AppUpdateException(
        'GitHub API returned ${response.statusCode}. Try again later.',
      );
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw AppUpdateException('Invalid response from GitHub Releases API.');
    }

    final tagName = body['tag_name'] as String? ?? '';
    if (tagName.isEmpty) {
      throw AppUpdateException('Release is missing tag_name.');
    }

    final versionString = parseReleaseVersionFromTag(tagName);
    final Version version;
    try {
      version = Version.parse(versionString);
    } on FormatException {
      throw AppUpdateException('Unrecognized release version: $tagName');
    }

    final assets = body['assets'];
    if (assets is! List || assets.isEmpty) {
      throw AppUpdateException('Release has no downloadable assets.');
    }

    final assetMaps = assets.whereType<Map<String, dynamic>>().toList();
    final assetNames = assetMaps
        .map((a) => a['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList();

    final kind = _installKindResolver();
    final androidSuffix = kind == AppUpdateInstallKind.androidApk
        ? androidApkAbiSuffix(preferArm64: preferAndroidArm64)
        : androidApkAbiSuffix();
    final assetName = selectReleaseAssetName(
      assetNames: assetNames,
      kind: kind,
      androidAbiSuffix: androidSuffix,
    );

    Map<String, dynamic>? chosen;
    for (final asset in assetMaps) {
      if (asset['name'] == assetName) {
        chosen = asset;
        break;
      }
    }
    if (chosen == null) {
      throw AppUpdateAssetNotFoundException(kind, assetNames);
    }

    final downloadUrl = chosen['browser_download_url'] as String? ?? '';
    if (downloadUrl.isEmpty) {
      throw AppUpdateException('Asset $assetName has no download URL.');
    }

    final fileSize = (chosen['size'] as num?)?.toInt() ?? 0;
    final releaseNotes = body['body'] as String? ?? '';
    final htmlUrl = body['html_url'] as String? ?? '';

    return AppReleaseInfo(
      version: version,
      tagName: tagName,
      releaseNotes: releaseNotes,
      downloadUrl: downloadUrl,
      assetName: assetName,
      fileSize: fileSize,
      htmlUrl: htmlUrl,
    );
  }

  /// Downloads [release] to a temp file; [onProgress] receives 0.0–1.0 when size known.
  Future<File> downloadRelease(
    AppReleaseInfo release, {
    void Function(double progress)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(release.downloadUrl));
    final info = await _packageInfoLoader();
    request.headers['User-Agent'] = _userAgent ?? 'TeamPilot/${info.version}';

    final streamed = await _httpClient.send(request);
    if (streamed.statusCode != 200) {
      throw AppUpdateException(
        'Download failed (${streamed.statusCode}).',
      );
    }

    final total = release.fileSize > 0
        ? release.fileSize
        : streamed.contentLength;
    final dir = await Directory.systemTemp.createTemp('teampilot_update_');
    final dest = File(p.join(dir.path, release.assetName));
    final sink = dest.openWrite();
    var received = 0;

    try {
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null && total != null && total > 0) {
          onProgress(received / total);
        }
      }
    } catch (e) {
      await sink.close();
      await dir.delete(recursive: true);
      rethrow;
    }

    await sink.close();
    if (onProgress != null && total != null && total > 0) {
      onProgress(1.0);
    }
    return dest;
  }
}

class AppUpdateException implements Exception {
  AppUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}
