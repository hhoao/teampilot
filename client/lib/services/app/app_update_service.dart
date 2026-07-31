import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import '../../config/app_update_config.dart';
import '../../models/app_release_info.dart';
import '../github/github_http.dart';
import '../remote_download/remote_download_catalog.dart';
import '../remote_download/remote_download_http.dart';
import '../remote_download/remote_download_resolver.dart';
import '../remote_download/remote_downloader.dart';
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
    String? githubToken,
    String? githubOwner,
    String? githubRepo,
    RemoteDownloadResolver? resolver,
    RemoteDownloader? downloader,
    RemoteDownloadHttp? downloadHttp,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _packageInfoLoader =
           packageInfoLoader ?? (() => PackageInfo.fromPlatform()),
       _installKindResolver =
           installKindResolver ?? resolveAppUpdateInstallKind,
       _userAgent = userAgent,
       _githubToken = githubToken,
       _githubOwner = githubOwner,
       _githubRepo = githubRepo {
    final effectiveResolver =
        resolver ?? RemoteDownloadResolver(RemoteDownloadCatalog.defaults());
    _downloadHttp =
        downloadHttp ??
        RemoteDownloadHttp(client: _httpClient, resolver: effectiveResolver);
    _downloader =
        downloader ??
        RemoteDownloader(client: _httpClient, resolver: effectiveResolver);
  }

  final http.Client _httpClient;
  final bool _ownsClient;
  final PackageInfoLoader _packageInfoLoader;
  final AppUpdateInstallKind Function() _installKindResolver;
  final String? _userAgent;
  final String? _githubToken;
  final String? _githubOwner;
  final String? _githubRepo;
  late final RemoteDownloadHttp _downloadHttp;
  late final RemoteDownloader _downloader;

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
    final preferArm64 = preferAndroidArm64 ?? await preferArm64AndroidApk();
    final current = await currentVersion();
    final release = await _fetchLatestRelease(preferAndroidArm64: preferArm64);
    if (current >= release.version) {
      return AppUpdateUpToDate();
    }
    return AppUpdateAvailable(release);
  }

  Future<AppReleaseInfo> _fetchLatestRelease({
    bool preferAndroidArm64 = true,
  }) async {
    try {
      return await _fetchLatestReleaseFromApi(
        preferAndroidArm64: preferAndroidArm64,
      );
    } on AppUpdateException catch (e) {
      if (!e.isRateLimited) rethrow;
      return _fetchLatestReleaseFallback(
        preferAndroidArm64: preferAndroidArm64,
      );
    }
  }

  Future<AppReleaseInfo> _fetchLatestReleaseFromApi({
    bool preferAndroidArm64 = true,
  }) async {
    final url = appUpdateLatestReleaseApiUrl(
      owner: _githubOwner,
      repo: _githubRepo,
    );
    final http.Response response;
    try {
      response = await _downloadHttp.get(
        Uri.parse(url),
        headers: await _apiHeaders(),
      );
    } on RemoteDownloadException catch (e) {
      throw _appUpdateExceptionFromRemoteDownload(e, api: true);
    }
    if (response.statusCode != 200) {
      throw AppUpdateException(
        githubApiErrorMessage(
          response.statusCode,
          responseHeaders: response.headers,
        ),
        isRateLimited: githubApiStatusIsRateLimited(response.statusCode),
      );
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw AppUpdateException('Invalid response from GitHub Releases API.');
    }

    return _releaseInfoFromApiBody(
      body,
      preferAndroidArm64: preferAndroidArm64,
    );
  }

  Future<AppReleaseInfo> _fetchLatestReleaseFallback({
    bool preferAndroidArm64 = true,
  }) async {
    final owner = _githubOwner ?? appUpdateGitHubOwner;
    final repo = _githubRepo ?? appUpdateGitHubRepo;
    final tagName = await _resolveLatestReleaseTagName(
      owner: owner,
      repo: repo,
    );
    if (tagName == null) {
      throw AppUpdateException(
        'Could not resolve the latest release without GitHub API access. '
        'Try again later or set GITHUB_TOKEN.',
      );
    }

    final versionString = parseReleaseVersionFromTag(tagName);
    final Version version;
    try {
      version = Version.parse(versionString);
    } on FormatException {
      throw AppUpdateException('Unrecognized release version: $tagName');
    }

    final kind = _installKindResolver();
    final androidSuffix = kind == AppUpdateInstallKind.androidApk
        ? androidApkAbiSuffix(preferArm64: preferAndroidArm64)
        : androidApkAbiSuffix();
    final assetName = buildExpectedReleaseAssetName(
      version: version,
      kind: kind,
      androidAbiSuffix: androidSuffix,
    );
    final downloadUrl = githubReleaseAssetDownloadUrl(
      owner: owner,
      repo: repo,
      tagName: tagName,
      assetName: assetName,
    );

    final headers = await _httpHeaders();
    final http.Response head;
    try {
      head = await _downloadHttp.head(
        Uri.parse(downloadUrl),
        headers: headers,
      );
    } on RemoteDownloadException catch (e) {
      throw _appUpdateExceptionFromRemoteDownload(e);
    }
    if (head.statusCode != 200) {
      throw AppUpdateAssetNotFoundException(kind, [assetName]);
    }

    final fileSize = int.tryParse(head.headers['content-length'] ?? '') ?? 0;
    return AppReleaseInfo(
      version: version,
      tagName: tagName,
      releaseNotes: '',
      downloadUrl: downloadUrl,
      assetName: assetName,
      fileSize: fileSize,
      htmlUrl: 'https://github.com/$owner/$repo/releases/tag/$tagName',
    );
  }

  Future<String?> _resolveLatestReleaseTagName({
    required String owner,
    required String repo,
  }) async {
    final pageUrl = appUpdateLatestReleasePageUrl(owner: owner, repo: repo);
    final headers = await _httpHeaders();
    try {
      final streamed = await _downloadHttp.send(
        (candidateUri) {
          final request = http.Request('GET', candidateUri)
            ..followRedirects = false
            ..headers.addAll(headers);
          return request;
        },
        Uri.parse(pageUrl),
      );
      await streamed.stream.drain();

      if (streamed.statusCode >= 300 && streamed.statusCode < 400) {
        final location = streamed.headers['location'];
        if (location != null) {
          final tag = parseReleaseTagFromGithubUrl(location);
          if (tag != null) return tag;
        }
      }
    } on RemoteDownloadException {
      // Fall through to releases.atom.
    }

    final atomUrl = 'https://github.com/$owner/$repo/releases.atom';
    try {
      final atomResponse = await _downloadHttp.get(
        Uri.parse(atomUrl),
        headers: headers,
      );
      if (atomResponse.statusCode != 200) return null;
      return _parseLatestTagFromAtom(atomResponse.body);
    } on RemoteDownloadException {
      return null;
    }
  }

  String? _parseLatestTagFromAtom(String body) {
    final linkMatch = RegExp(
      r'<link[^>]+href="https://github\.com/[^"]+/releases/tag/([^"?#]+)"',
    ).firstMatch(body);
    final fromLink = linkMatch?.group(1)?.trim();
    if (fromLink != null && fromLink.isNotEmpty) return fromLink;

    final titleMatch = RegExp(
      r'<entry>\s*<title>([^<]+)</title>',
    ).firstMatch(body);
    final title = titleMatch?.group(1)?.trim();
    if (title != null && title.isNotEmpty) return title;
    return null;
  }

  AppReleaseInfo _releaseInfoFromApiBody(
    Map<String, dynamic> body, {
    required bool preferAndroidArm64,
  }) {
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

  Future<Map<String, String>> _apiHeaders() async {
    return githubApiHeaders(
      userAgent: await _resolvedUserAgent(),
      token: _githubToken,
    );
  }

  Future<Map<String, String>> _httpHeaders() async {
    return githubHttpHeaders(userAgent: await _resolvedUserAgent());
  }

  Future<String> _resolvedUserAgent() async {
    final override = _userAgent;
    if (override != null) return override;
    final info = await _packageInfoLoader();
    return 'TeamPilot/${info.version}';
  }

  /// Downloads [release] to a temp file; [onProgress] receives 0.0–1.0 when size known.
  Future<File> downloadRelease(
    AppReleaseInfo release, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final file = await _downloader.fetch(
        Uri.parse(release.downloadUrl),
        destFileName: release.assetName,
        headers: await _httpHeaders(),
        onProgress: (received, total) {
          if (onProgress != null && total != null && total > 0) {
            onProgress(received / total);
          }
        },
      );
      if (onProgress != null && release.fileSize > 0) {
        onProgress(1.0);
      }
      return file;
    } on RemoteDownloadException catch (e) {
      throw AppUpdateException(e.message);
    }
  }

  AppUpdateException _appUpdateExceptionFromRemoteDownload(
    RemoteDownloadException error, {
    bool api = false,
  }) {
    if (api) {
      for (final attempt in error.attempts) {
        final status = attempt.statusCode;
        if (status != null) {
          return AppUpdateException(
            githubApiErrorMessage(status),
            isRateLimited: githubApiStatusIsRateLimited(status),
          );
        }
      }
    }
    return AppUpdateException(error.message);
  }
}

class AppUpdateException implements Exception {
  AppUpdateException(this.message, {this.isRateLimited = false});

  final String message;
  final bool isRateLimited;

  @override
  String toString() => message;
}
