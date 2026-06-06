import '../app_provider_config.dart';

/// Built-in Cursor CLI provider presets.
class CursorProviderPresets {
  const CursorProviderPresets._();

  static const account = AppProviderPreset(
    id: 'cursor-account',
    label: 'Cursor Account',
    template: AppProviderConfig(
      id: 'cursor-account',
      cli: CliTool.cursor,
      name: 'Cursor Account',
      websiteUrl: 'https://cursor.com',
      apiKeyUrl: '',
      category: AppProviderCategory.official,
      apiKeyField: 'api_key',
      baseUrl: '',
      defaultModel: '',
      icon: 'cursor',
      iconColor: '',
      isOfficial: true,
      isPartner: false,
      partnerPromotionKey: '',
      endpointCandidates: [],
      config: {},
    ),
  );

  static const all = <AppProviderPreset>[account];

  static AppProviderPreset? byId(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}
