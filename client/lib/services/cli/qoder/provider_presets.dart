import '../../../models/app_provider_config.dart';

abstract final class QoderProviderPresets {
  const QoderProviderPresets._();

  static const global = <AppProviderPreset>[
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

  static const cn = <AppProviderPreset>[
    AppProviderPreset(
      id: 'qoder-cn',
      label: 'Qoder CN',
      template: AppProviderConfig(
        id: 'qoder-cn',
        cli: CliTool.qoderCn,
        name: 'Qoder CN',
        websiteUrl: 'https://qoder.com.cn',
        category: AppProviderCategory.official,
        isOfficial: true,
        apiKeyField: 'api_key',
        defaultModel: 'auto',
        icon: 'qoder',
        notes:
            'Isolated login: Sign in opens a Qoder CN login terminal that does '
            'not touch your global Qoder account.',
      ),
    ),
  ];

  static const all = <AppProviderPreset>[...global, ...cn];

  static AppProviderPreset? byId(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}
