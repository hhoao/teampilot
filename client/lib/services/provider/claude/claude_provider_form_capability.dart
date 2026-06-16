import 'package:flutter/widgets.dart';

import '../../../models/app_provider_config.dart';
import '../../../models/provider_presets/claude_provider_presets.dart';
import '../../../widgets/app_provider/claude_provider_form_section.dart';
import '../../cli/registry/capabilities/provider_form_capability.dart';

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
    // Endpoint, credential field, and model live on the canonical top-level
    // fields (baseUrl / apiKeyField / defaultModel) and are materialized at
    // launch — the form never freezes derived env into the record here.
    return Map<String, Object?>.from(input.config);
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
          onApiKeyFieldChanged: props.onApiKeyFieldChanged,
        ),
      ],
    );
  }

  Map<String, Object?> _extraFromConfig(Map<String, Object?> config) => const {};
}
