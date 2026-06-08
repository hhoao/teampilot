import '../../../models/app_provider_config.dart';
import '../../../models/provider_presets/codex_provider_presets.dart';
import '../../cli/registry/capabilities/provider_form_capability.dart';
import '../passthrough_provider_form_capability.dart';

abstract final class CodexFormExtraKeys {
  static const effort = 'effort';
}

final class CodexProviderFormCapability extends PassthroughProviderFormCapability {
  const CodexProviderFormCapability();

  @override
  List<AppProviderPreset> get presets => CodexProviderPresets.all;

  @override
  Map<String, Object?> defaultConfig() => {'auth': <String, Object?>{}};

  @override
  String defaultApiKeyField() => 'OPENAI_API_KEY';

  @override
  Map<String, Object?> extraFromExisting(AppProviderConfig? existing) {
    final config = existing?.config ?? defaultConfig();
    return {
      CodexFormExtraKeys.effort:
          config['model_reasoning_effort']?.toString() ?? '',
    };
  }

  @override
  Map<String, Object?> extraFromPreset(AppProviderPreset preset) => {
    CodexFormExtraKeys.effort:
        preset.template.config['model_reasoning_effort']?.toString() ?? '',
  };

  @override
  Map<String, Object?> buildConfig(ProviderFormInput input) {
    final config = Map<String, Object?>.from(input.config);
    final effort = input.extra[CodexFormExtraKeys.effort]?.toString().trim() ?? '';
    if (effort.isEmpty) {
      config.remove('model_reasoning_effort');
    } else {
      config['model_reasoning_effort'] = effort;
    }
    return config;
  }
}
