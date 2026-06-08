import 'package:flutter/widgets.dart';

import '../../../models/app_provider_config.dart';
import '../../../models/provider_presets/claude_provider_presets.dart';
import '../../../widgets/app_provider/claude_provider_form_section.dart';
import '../../cli/registry/capabilities/provider_form_capability.dart';

abstract final class ClaudeFormExtraKeys {
  static const apiFormat = 'apiFormat';
  static const haikuModel = 'haikuModel';
  static const sonnetModel = 'sonnetModel';
  static const opusModel = 'opusModel';
}

const _apiKeyFields = ['ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY'];

final class ClaudeProviderFormCapability implements ProviderFormCapability {
  const ClaudeProviderFormCapability();

  @override
  List<AppProviderPreset> get presets => ClaudeProviderPresets.all;

  @override
  Map<String, Object?> defaultConfig() => {'env': <String, Object?>{}};

  @override
  String defaultApiKeyField() => 'ANTHROPIC_AUTH_TOKEN';

  @override
  String normalizeApiKeyField(String? raw) {
    final value = raw?.trim() ?? '';
    return _apiKeyFields.contains(value) ? value : defaultApiKeyField();
  }

  @override
  Map<String, Object?> configForCliSwitch() => defaultConfig();

  @override
  Map<String, Object?> extraFromExisting(AppProviderConfig? existing) {
    final config = existing?.config ?? defaultConfig();
    return _extraFromConfig(config);
  }

  @override
  Map<String, Object?> extraFromPreset(AppProviderPreset preset) =>
      _extraFromConfig(preset.template.config);

  @override
  Map<String, Object?> buildConfig(ProviderFormInput input) {
    final config = Map<String, Object?>.from(input.config);
    final env = _envFrom(config);

    void setOrRemove(String key, String value) {
      if (value.isEmpty) {
        env.remove(key);
      } else {
        env[key] = value;
      }
    }

    setOrRemove('ANTHROPIC_BASE_URL', input.baseUrl.trim());
    setOrRemove('ANTHROPIC_MODEL', input.defaultModel.trim());
    setOrRemove(
      'ANTHROPIC_DEFAULT_HAIKU_MODEL',
      input.extra[ClaudeFormExtraKeys.haikuModel]?.toString() ?? '',
    );
    setOrRemove(
      'ANTHROPIC_DEFAULT_SONNET_MODEL',
      input.extra[ClaudeFormExtraKeys.sonnetModel]?.toString() ?? '',
    );
    setOrRemove(
      'ANTHROPIC_DEFAULT_OPUS_MODEL',
      input.extra[ClaudeFormExtraKeys.opusModel]?.toString() ?? '',
    );

    config['env'] = env;
    config['apiFormat'] =
        input.extra[ClaudeFormExtraKeys.apiFormat]?.toString() ?? 'anthropic';
    config['api_key_field'] = input.apiKeyField;
    return config;
  }

  @override
  Widget buildExtraSection(
    BuildContext context,
    ProviderFormSectionProps props,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        ClaudeProviderFormSection(
          apiKeyField: props.apiKeyField,
          extra: props.extra,
          onExtraChanged: props.onExtraChanged,
          onApiKeyFieldChanged: props.onApiKeyFieldChanged,
        ),
      ],
    );
  }

  Map<String, Object?> _extraFromConfig(Map<String, Object?> config) {
    final env = _envFrom(config);
    return {
      ClaudeFormExtraKeys.apiFormat:
          config['apiFormat']?.toString() ?? 'anthropic',
      ClaudeFormExtraKeys.haikuModel:
          env['ANTHROPIC_DEFAULT_HAIKU_MODEL']?.toString() ?? '',
      ClaudeFormExtraKeys.sonnetModel:
          env['ANTHROPIC_DEFAULT_SONNET_MODEL']?.toString() ?? '',
      ClaudeFormExtraKeys.opusModel:
          env['ANTHROPIC_DEFAULT_OPUS_MODEL']?.toString() ?? '',
    };
  }

  Map<String, Object?> _envFrom(Map<String, Object?> config) {
    final raw = config['env'];
    return raw is Map ? Map<String, Object?>.from(raw) : <String, Object?>{};
  }
}
