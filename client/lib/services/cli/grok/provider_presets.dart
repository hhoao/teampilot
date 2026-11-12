import '../../../models/app_provider_config.dart';
import 'grok_constants.dart';

/// Built-in Grok provider templates.
///
/// The official xAI row supports both an API key (`XAI_API_KEY` injected into
/// the isolated process env, never written to disk) and a device-code OAuth
/// login. The login runs against an isolated `GROK_HOME` so it does not read
/// or modify `~/.grok/auth.json`.
abstract final class GrokProviderPresets {
  const GrokProviderPresets._();

  static const all = <AppProviderPreset>[
    AppProviderPreset(
      id: 'xai',
      label: 'xAI (Grok)',
      template: AppProviderConfig(
        id: 'xai',
        cli: CliTool.grok,
        name: 'xAI (Grok)',
        websiteUrl: 'https://x.ai',
        apiKeyUrl: 'https://console.x.ai/team/default/api-keys',
        category: AppProviderCategory.official,
        isOfficial: true,
        apiKeyField: 'api_key',
        defaultModel: GrokConstants.defaultModel,
        icon: 'grok',
        notes:
            'Use an xAI API key, or Sign in to authorize with your grok.com '
            'account. Sign-in is isolated from your global ~/.grok login.',
      ),
    ),
  ];

  static AppProviderPreset? byId(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}
