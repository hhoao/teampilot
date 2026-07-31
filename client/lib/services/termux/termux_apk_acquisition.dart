import 'dart:convert';
import 'dart:io';

import 'package:android_package_installer/android_package_installer.dart';

import '../app/app_update_service.dart';
import '../github/github_http.dart';
import '../remote_download/remote_download_http.dart';
import '../remote_download/remote_downloader.dart';
import 'termux_apk_asset.dart';

enum TermuxApkAcquirePhase {
  success,
  apiFailed,
  assetNotFound,
  downloadFailed,
  installFailed,
  installNoResult,
}

class TermuxApkAcquireResult {
  const TermuxApkAcquireResult._({
    required this.success,
    required this.phase,
    this.assetName,
    this.apkFile,
    this.installStatusCode,
    this.errorMessage,
  });

  const TermuxApkAcquireResult.success({
    required String assetName,
    required File apkFile,
    required int installStatusCode,
  }) : this._(
         success: true,
         phase: TermuxApkAcquirePhase.success,
         assetName: assetName,
         apkFile: apkFile,
         installStatusCode: installStatusCode,
       );

  const TermuxApkAcquireResult.failure({
    required TermuxApkAcquirePhase phase,
    required String errorMessage,
    String? assetName,
    File? apkFile,
    int? installStatusCode,
  }) : this._(
         success: false,
         phase: phase,
         assetName: assetName,
         apkFile: apkFile,
         installStatusCode: installStatusCode,
         errorMessage: errorMessage,
       );

  final bool success;
  final TermuxApkAcquirePhase phase;
  final String? assetName;
  final File? apkFile;
  final int? installStatusCode;
  final String? errorMessage;
}

typedef TermuxApkInstaller = Future<int?> Function(String apkPath);

/// Discovers the latest Termux APK, downloads it, and launches the installer.
class TermuxApkAcquisition {
  TermuxApkAcquisition({
    required RemoteDownloadHttp http,
    required RemoteDownloader downloader,
    TermuxApkInstaller? installApk,
    String? githubToken,
    String? userAgent,
  }) : _http = http,
       _downloader = downloader,
       _installApk =
           installApk ??
           ((apkPath) => AndroidPackageInstaller.installApk(apkFilePath: apkPath)),
       _githubToken = githubToken,
       _userAgent = userAgent;

  final RemoteDownloadHttp _http;
  final RemoteDownloader _downloader;
  final TermuxApkInstaller _installApk;
  final String? _githubToken;
  final String? _userAgent;

  Future<TermuxApkAcquireResult> downloadAndInstall({
    bool? preferArm64,
    void Function(int received, int? total)? onProgress,
  }) async {
    final prefer = preferArm64 ?? await AppUpdateService.preferArm64AndroidApk();

    final releaseResult = await _fetchLatestReleaseBody();
    if (releaseResult is TermuxApkAcquireResult) {
      return releaseResult;
    }
    final releaseBody = releaseResult as Map<String, dynamic>;

    final assets = releaseBody['assets'];
    if (assets is! List) {
      return TermuxApkAcquireResult.failure(
        phase: TermuxApkAcquirePhase.assetNotFound,
        errorMessage: 'Release is missing assets.',
      );
    }

    final assetMaps = assets
        .whereType<Map>()
        .map((asset) => Map<String, dynamic>.from(asset))
        .toList();

    late final String assetName;
    late final String downloadUrl;
    try {
      assetName = selectTermuxApkAssetName(
        assets: assetMaps,
        preferArm64: prefer,
      );
      downloadUrl = selectTermuxApkDownloadUrl(
        assets: assetMaps,
        preferArm64: prefer,
      );
    } on TermuxApkAssetNotFoundException catch (error) {
      return TermuxApkAcquireResult.failure(
        phase: TermuxApkAcquirePhase.assetNotFound,
        errorMessage: error.toString(),
      );
    }

    late final File apkFile;
    try {
      apkFile = await _downloader.fetch(
        Uri.parse(downloadUrl),
        destFileName: assetName,
        headers: githubHttpHeaders(userAgent: _userAgent ?? kGithubHttpUserAgent),
        onProgress: onProgress,
      );
    } on RemoteDownloadException catch (error) {
      return TermuxApkAcquireResult.failure(
        phase: TermuxApkAcquirePhase.downloadFailed,
        errorMessage: error.message,
        assetName: assetName,
      );
    } catch (error) {
      return TermuxApkAcquireResult.failure(
        phase: TermuxApkAcquirePhase.downloadFailed,
        errorMessage: '$error',
        assetName: assetName,
      );
    }

    final statusCode = await _installApk(apkFile.path);
    if (statusCode == null) {
      return TermuxApkAcquireResult.failure(
        phase: TermuxApkAcquirePhase.installNoResult,
        errorMessage: 'APK install returned no status.',
        assetName: assetName,
        apkFile: apkFile,
      );
    }

    final status = PackageInstallerStatus.byCode(statusCode);
    if (status != PackageInstallerStatus.success) {
      return TermuxApkAcquireResult.failure(
        phase: TermuxApkAcquirePhase.installFailed,
        errorMessage: 'APK install failed: ${status.name}',
        assetName: assetName,
        apkFile: apkFile,
        installStatusCode: statusCode,
      );
    }

    return TermuxApkAcquireResult.success(
      assetName: assetName,
      apkFile: apkFile,
      installStatusCode: statusCode,
    );
  }

  Future<Object> _fetchLatestReleaseBody() async {
    try {
      final response = await _http.get(
        termuxLatestReleaseApiUri(),
        headers: githubApiHeaders(
          userAgent: _userAgent ?? kGithubHttpUserAgent,
          token: _githubToken,
        ),
      );

      if (response.statusCode != 200) {
        return TermuxApkAcquireResult.failure(
          phase: TermuxApkAcquirePhase.apiFailed,
          errorMessage: githubApiErrorMessage(
            response.statusCode,
            responseHeaders: response.headers,
          ),
        );
      }

      return Map<String, dynamic>.from(
        jsonDecode(response.body) as Map<dynamic, dynamic>,
      );
    } on RemoteDownloadException catch (error) {
      return TermuxApkAcquireResult.failure(
        phase: TermuxApkAcquirePhase.apiFailed,
        errorMessage: error.message,
      );
    } on FormatException {
      return TermuxApkAcquireResult.failure(
        phase: TermuxApkAcquirePhase.apiFailed,
        errorMessage: 'Invalid response from GitHub Releases API.',
      );
    }
  }
}
