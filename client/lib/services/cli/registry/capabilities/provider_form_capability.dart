import 'package:flutter/widgets.dart';

import '../../../../models/app_provider_config.dart';
import '../cli_capability.dart';

/// Values collected from the provider form shell before [buildConfig].
@immutable
class ProviderFormInput {
  const ProviderFormInput({
    required this.baseUrl,
    required this.defaultModel,
    required this.apiKeyField,
    required this.config,
    this.extra = const {},
  });

  final String baseUrl;
  final String defaultModel;
  final String apiKeyField;
  final Map<String, Object?> config;
  final Map<String, Object?> extra;
}

/// Props for CLI-specific form sections rendered below common fields.
@immutable
class ProviderFormSectionProps {
  const ProviderFormSectionProps({
    required this.config,
    required this.apiKeyField,
    required this.baseUrl,
    required this.defaultModel,
    required this.extra,
    required this.onExtraChanged,
    required this.onApiKeyFieldChanged,
  });

  final Map<String, Object?> config;
  final String apiKeyField;
  final String baseUrl;
  final String defaultModel;
  final Map<String, Object?> extra;
  final ValueChanged<Map<String, Object?>> onExtraChanged;
  final ValueChanged<String> onApiKeyFieldChanged;
}

/// Per-CLI provider add/edit form: presets, defaults, config merge, extra UI.
abstract interface class ProviderFormCapability implements CliCapability {
  List<AppProviderPreset> get presets;

  Map<String, Object?> defaultConfig();

  String defaultApiKeyField();

  String normalizeApiKeyField(String? raw);

  Map<String, Object?> configForCliSwitch();

  Map<String, Object?> extraFromExisting(AppProviderConfig? existing);

  Map<String, Object?> extraFromPreset(AppProviderPreset preset);

  Map<String, Object?> buildConfig(ProviderFormInput input);

  Widget buildExtraSection(BuildContext context, ProviderFormSectionProps props);
}
