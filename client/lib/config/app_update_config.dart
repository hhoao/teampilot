/// GitHub Releases source for in-app TeamPilot updates.
///
/// Override at build time for forks or mirrors:
/// `--dart-define=APP_UPDATE_GITHUB_OWNER=...`
/// `--dart-define=APP_UPDATE_GITHUB_REPO=...`
const String appUpdateGitHubOwner = String.fromEnvironment(
  'APP_UPDATE_GITHUB_OWNER',
  defaultValue: 'hhoao',
);

const String appUpdateGitHubRepo = String.fromEnvironment(
  'APP_UPDATE_GITHUB_REPO',
  defaultValue: 'teampilot',
);

/// Prefix used in CI release asset filenames (`teampilot-1.0.0-linux.deb`, …).
const String appUpdateReleaseArtifactSlug = 'teampilot';

String appUpdateLatestReleaseApiUrl({
  String? owner,
  String? repo,
}) {
  final o = owner ?? appUpdateGitHubOwner;
  final r = repo ?? appUpdateGitHubRepo;
  return 'https://api.github.com/repos/$o/$r/releases/latest';
}

String appUpdateLatestReleasePageUrl({String? owner, String? repo}) {
  final o = owner ?? appUpdateGitHubOwner;
  final r = repo ?? appUpdateGitHubRepo;
  return 'https://github.com/$o/$r/releases/latest';
}

String appUpdateGitHubRepoPageUrl({String? owner, String? repo}) {
  final o = owner ?? appUpdateGitHubOwner;
  final r = repo ?? appUpdateGitHubRepo;
  return 'https://github.com/$o/$r';
}

String appUpdateGitHubReleasesPageUrl({String? owner, String? repo}) {
  final o = owner ?? appUpdateGitHubOwner;
  final r = repo ?? appUpdateGitHubRepo;
  return 'https://github.com/$o/$r/releases';
}
