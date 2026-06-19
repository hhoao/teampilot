import '../../../models/app_provider_config.dart';
import '../../../models/provider_presets/opencode_provider_presets.dart';
import '../../cli/registry/capabilities/provider_form_capability.dart';
import '../passthrough_provider_form_capability.dart';

abstract final class OpencodeFormExtraKeys {
  static const effort = 'effort';
}

final class OpencodeProviderFormCapability
    extends PassthroughProviderFormCapability {
  const OpencodeProviderFormCapability();

  @override
  List<AppProviderPreset> get presets => OpencodeProviderPresets.all;

  @override
  Map<String, Object?> defaultConfig() => const {};

  @override
  String defaultApiKeyField() => 'api_key';

  @override
  Map<String, Object?> extraFromExisting(AppProviderConfig? existing) {
    final config = existing?.config ?? defaultConfig();
    return {
      OpencodeFormExtraKeys.effort:
          config['reasoningEffort']?.toString() ?? '',
    };
  }

  @override
  Map<String, Object?> extraFromPreset(AppProviderPreset preset) => {
    OpencodeFormExtraKeys.effort:
        preset.template.config['reasoningEffort']?.toString() ?? '',
  };

  @override
  Map<String, Object?> buildConfig(ProviderFormInput input) {
    final config = Map<String, Object?>.from(input.config);
    final effort =
        input.extra[OpencodeFormExtraKeys.effort]?.toString().trim() ?? '';
    if (effort.isEmpty) {
      config.remove('reasoningEffort');
    } else {
      config['reasoningEffort'] = effort;
    }
    return config;
  }
}
