/// Official TeamPilot GitHub OAuth App client id for Device Flow.
///
/// Override: `--dart-define=GITHUB_OAUTH_CLIENT_ID=...`
/// Empty default disables Device Flow (Advanced PAT / env still work).
const String githubOauthClientId = String.fromEnvironment(
  'GITHUB_OAUTH_CLIENT_ID',
  defaultValue: '',
);

bool get githubDeviceFlowAvailable => githubOauthClientId.trim().isNotEmpty;
