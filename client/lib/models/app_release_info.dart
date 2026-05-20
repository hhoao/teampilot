import 'package:equatable/equatable.dart';
import 'package:pub_semver/pub_semver.dart';

/// Parsed GitHub Release metadata for the current platform.
class AppReleaseInfo extends Equatable {
  const AppReleaseInfo({
    required this.version,
    required this.tagName,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.assetName,
    required this.fileSize,
    required this.htmlUrl,
  });

  final Version version;
  final String tagName;
  final String releaseNotes;
  final String downloadUrl;
  final String assetName;
  final int fileSize;
  final String htmlUrl;

  @override
  List<Object?> get props => [
    version,
    tagName,
    releaseNotes,
    downloadUrl,
    assetName,
    fileSize,
    htmlUrl,
  ];
}

/// Result of comparing the running app version to the latest release.
sealed class AppUpdateCheckResult {}

class AppUpdateUpToDate extends AppUpdateCheckResult {}

class AppUpdateAvailable extends AppUpdateCheckResult {
  AppUpdateAvailable(this.release);

  final AppReleaseInfo release;
}
