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
  defaultValue: 'flashskyai-ui',
);

String appUpdateLatestReleaseApiUrl({
  String? owner,
  String? repo,
}) {
  final o = owner ?? appUpdateGitHubOwner;
  final r = repo ?? appUpdateGitHubRepo;
  return 'https://api.github.com/repos/$o/$r/releases/latest';
}
