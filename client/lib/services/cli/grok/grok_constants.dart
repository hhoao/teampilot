/// Official Grok Build CLI (`grok`) constants.
///
/// Grok is ACP-only inside TeamPilot: sessions are terminal-less and every
/// config/credential path is derived from the injected `GROK_HOME` so the
/// user's global `~/.grok` store is never modified.
abstract final class GrokConstants {
  const GrokConstants._();

  static const executableName = 'grok';
  static const displayName = 'Grok CLI';

  /// Overrides the config root (docs: `~/.grok` by default).
  static const homeEnvKey = 'GROK_HOME';

  /// API-key auth, injected into the ACP/headless process env only.
  static const apiKeyEnvKey = 'XAI_API_KEY';

  /// Official installer.
  static const installUrl = 'https://x.ai/cli/install.sh';
  static const powershellInstallUrl = 'https://x.ai/cli/install.ps1';

  static const authFileName = 'auth.json';
  static const configFileName = 'config.toml';
  static const usageFileName = 'acp-usage.jsonl';

  /// Login/provider credential copies live under the home plane.
  static const authNamespace = 'grok';
  static const authMarkerFileName = '.grok-provider';

  /// grok External Auth Provider command (injected into the agent env).
  static const authProviderCommandEnvKey = 'GROK_AUTH_PROVIDER_COMMAND';

  /// Per-seat shim configuration (endpoint + token, 0600, no access token).
  static const leaseConfigFileName = 'credential-lease.json';

  /// Shim written into `<GROK_HOME>/bin/`.
  static const leaseShimFileName = 'teampilot-grok-auth';

  /// ACP authenticate method id that triggers the external auth provider.
  static const oauthMethodId = 'grok.com';

  static const defaultProviderId = 'xai';
  static const defaultModel = 'grok-4.7';
}
