import '../../../models/app_provider_config.dart';

/// Built-in Antigravity provider templates.
///
/// The official row signs in with a Google account through the CLI's own
/// login terminal (`auth.type: oauth-personal`). The Gemini API-key row uses
/// `GEMINI_API_KEY` from the process env; the key never lands on disk.
///
/// ADC (`agent-platform`) has no preset: the isolated per-session `HOME` also
/// isolates `$HOME/.config/gcloud`, so a host ADC login would not be visible to
/// the adapter. `AntigravityProviderCapability` still honours a custom /
/// cloud-provider row that pins `authMode: agent-platform` (for a pre-seeded
/// home or explicit credentials).
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
  ];
}
