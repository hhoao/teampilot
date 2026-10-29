import '../../../models/app_provider_config.dart';

/// Built-in Antigravity provider templates.
///
/// The official row signs in with a Google account through the CLI's own
/// login terminal (`auth.type: oauth-personal`). The Gemini API-key row uses
/// `GEMINI_API_KEY` from the process env; the key never lands on disk. The ADC
/// row reuses the host's Application Default Credentials through the adapter's
/// `agent-platform` auth mode.
abstract final class AntigravityProviderPresets {
  const AntigravityProviderPresets._();

  static const all = <AppProviderPreset>[
    AppProviderPreset(
      id: 'antigravity',
      label: 'Google account',
      template: AppProviderConfig(
        id: 'antigravity',
        cli: CliTool.antigravity,
        name: 'Google account',
        websiteUrl: 'https://antigravity.google',
        category: AppProviderCategory.official,
        isOfficial: true,
        apiKeyField: 'api_key',
        defaultModel: 'gemini-3.8-flash-high',
        icon: 'gemini',
        notes:
            'Sign in with a Google account. The account is stored in the OS '
            'keyring and shared by all Antigravity sessions and every official '
            'provider row.',
        config: {'authMode': 'oauth-personal'},
      ),
    ),
    AppProviderPreset(
      id: 'gemini-api-key',
      label: 'Gemini API key',
      template: AppProviderConfig(
        id: 'gemini-api-key',
        cli: CliTool.antigravity,
        name: 'Gemini API key',
        websiteUrl: 'https://ai.google.dev',
        apiKeyUrl: 'https://aistudio.google.com/apikey',
        category: AppProviderCategory.custom,
        apiKeyField: 'api_key',
        defaultModel: 'gemini-3.8-flash-high',
        icon: 'gemini',
        config: {'authMode': 'gemini-api-key'},
      ),
    ),
    AppProviderPreset(
      id: 'agent-platform',
      label: 'Google Cloud ADC',
      template: AppProviderConfig(
        id: 'agent-platform',
        cli: CliTool.antigravity,
        name: 'Google Cloud ADC',
        websiteUrl: 'https://cloud.google.com/docs/authentication',
        category: AppProviderCategory.cloudProvider,
        apiKeyField: 'api_key',
        defaultModel: 'gemini-3.8-flash-high',
        icon: 'gemini',
        notes:
            'Uses Application Default Credentials from the host '
            '(`gcloud auth application-default login`). Set "project" and '
            '"location" in the advanced config.',
        config: {
          'authMode': 'agent-platform',
          'project': '',
          'location': 'us-central1',
        },
      ),
    ),
  ];
}
