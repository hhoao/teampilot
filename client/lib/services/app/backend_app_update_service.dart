import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../models/app_models.dart';
import '../../utils/format_bytes.dart';
import 'app_update_asset_selector.dart';

/// Downloads release packages from the TeamPilot backend (not GitHub Releases).
class BackendAppUpdateService {
  BackendAppUpdateService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client(),
      _ownsClient = httpClient == null;

  final http.Client _httpClient;
  final bool _ownsClient;

  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }

  /// Resolves the URL used for in-app download.
  String resolveDownloadUrl(AppUpdateInfo info, AppApplicationRespVO app) {
    final fromInfo = info.downloadUrl?.trim();
    if (fromInfo != null && fromInfo.isNotEmpty) {
      return fromInfo;
    }
    final fromVersion = info.latestVersion?.downloadUrl?.trim();
    if (fromVersion != null && fromVersion.isNotEmpty) {
      return fromVersion;
    }
    throw BackendAppUpdateException('Download URL not available');
  }

  /// Guesses a filename when the download URL has no useful basename.
  static String suggestedPackageFileName({
    required AppApplicationRespVO app,
    required String downloadUrl,
  }) {
    final fromUrl = p.basename(Uri.parse(downloadUrl).path);
    if (fromUrl.isNotEmpty && fromUrl != '/' && p.extension(fromUrl).isNotEmpty) {
      return fromUrl;
    }

    final slug = _fileSlug(app.name);
    final version = app.version;
    return switch (resolveAppUpdateInstallKind()) {
      AppUpdateInstallKind.windowsSetup => '$slug-$version-setup.exe',
      AppUpdateInstallKind.macosDmg => '$slug-$version.dmg',
      AppUpdateInstallKind.linuxAppImage => '$slug-$version.appimage',
      AppUpdateInstallKind.linuxDeb => '$slug-$version-linux.deb',
      AppUpdateInstallKind.androidApk => '$slug-$version-arm64-v8a.apk',
    };
  }

  /// Whether the downloaded file extension matches this OS installer type.
  static bool packageMatchesCurrentPlatform(String filePath) {
    final low = filePath.toLowerCase();
    if (Platform.isAndroid) return low.endsWith('.apk');
    if (Platform.isWindows) {
      return low.endsWith('.exe') || low.endsWith('.msi');
    }
    if (Platform.isMacOS) return low.endsWith('.dmg') || low.endsWith('.pkg');
    if (Platform.isLinux) {
      return low.endsWith('.appimage') ||
          low.endsWith('.deb') ||
          low.endsWith('.rpm');
    }
    return false;
  }

  static String _fileSlug(String name) {
    final trimmed = name.trim().toLowerCase();
    if (trimmed.isEmpty) return 'teampilot';
    return trimmed.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(
      RegExp(r'^-+|-+$'),
      '',
    );
  }

  /// Follows redirect chains for backend download API endpoints.
  static Future<String> resolveRedirectedUrl(String url) async {
    final client = HttpClient();
    try {
      var currentUrl = url;
      var redirectCount = 0;
      const maxRedirects = 10;

      while (redirectCount < maxRedirects) {
        final currentUri = Uri.parse(currentUrl);
        final request = await client.getUrl(currentUri);
        request.followRedirects = false;
        final response = await request.close();

        if (response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers.value('location');
          if (location == null || location.isEmpty) break;
          currentUrl = location.startsWith('http')
              ? location
              : currentUri.resolve(location).toString();
          redirectCount++;
          await response.drain();
          continue;
        }
        await response.drain();
        break;
      }
      return currentUrl;
    } finally {
      client.close();
    }
  }

  Future<String> resolveFinalDownloadUrl(String url) async {
    if (url.contains('/app/download/') || url.contains('/autoclip/app/download/')) {
      return resolveRedirectedUrl(url);
    }
    return url;
  }

  /// Downloads an update package for the current platform (apk, exe, dmg, …).
  Future<File> downloadPackage({
    required String url,
    required String fileName,
    void Function(double progress, String statusLabel)? onProgress,
  }) async {
    final finalUrl = await resolveFinalDownloadUrl(url);
    final request = http.Request('GET', Uri.parse(finalUrl));
    final streamed = await _httpClient.send(request);
    if (streamed.statusCode != 200) {
      throw BackendAppUpdateException(
        'Download failed (${streamed.statusCode})',
      );
    }

    final total = streamed.contentLength;
    final dir = await _downloadDirectory();
    final dest = File(p.join(dir.path, fileName));
    if (await dest.exists()) {
      await dest.delete();
    }

    final sink = dest.openWrite();
    var received = 0;
    try {
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null && total != null && total > 0) {
          onProgress(
            received / total,
            '${formatBytesSize(received.toDouble())}/${formatBytesSize(total.toDouble())}',
          );
        } else if (onProgress != null) {
          onProgress(0, formatBytesSize(received.toDouble()));
        }
      }
    } catch (e) {
      await sink.close();
      if (await dest.exists()) await dest.delete();
      rethrow;
    }
    await sink.close();

    if (onProgress != null && total != null && total > 0) {
      onProgress(1, formatBytesSize(total.toDouble()));
    }
    return dest;
  }

  Future<Directory> _downloadDirectory() async {
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        final downloads = Directory(p.join(external.path, 'updates'));
        if (!await downloads.exists()) {
          await downloads.create(recursive: true);
        }
        return downloads;
      }
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        final dir = Directory(p.join(downloads.path, 'TeamPilot', 'updates'));
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return dir;
      }
    }

    final temp = await getTemporaryDirectory();
    final dir = Directory(p.join(temp.path, 'teampilot_updates'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}

class BackendAppUpdateException implements Exception {
  BackendAppUpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}
