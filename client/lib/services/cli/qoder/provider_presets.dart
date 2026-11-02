import '../../../models/app_provider_config.dart';

abstract final class QoderProviderPresets {
  const QoderProviderPresets._();

  static const all = <AppProviderPreset>[
    AppProviderPreset(
      id: 'qoder',
      label: 'Qoder',
      template: AppProviderConfig(
        id: 'qoder',
        cli: CliTool.qoder,
        name: 'Qoder',
        websiteUrl: 'https://qoder.com',
        category: AppProviderCategory.official,
        isOfficial: true,
        apiKeyField: 'api_key',
        defaultModel: 'auto',
        icon: 'qoder',
        notes:
            'Isolated login: Sign in opens a Qoder login terminal that does '
            'not touch your global ~/.qoder account.',
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
