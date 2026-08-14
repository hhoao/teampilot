import 'package:flutter/widgets.dart';

import '../../models/app_provider_config.dart';
import '../cli/registry/capabilities/provider_form_capability.dart';

/// Default form behavior for CLIs without advanced provider fields.
mixin PassthroughProviderFormDefaults {
  String defaultApiKeyField();
  Map<String, Object?> defaultConfig();

  String normalizeApiKeyField(String? raw) {
    final value = raw?.trim() ?? '';
    return value.isEmpty ? defaultApiKeyField() : value;
  }

  Map<String, Object?> configForCliSwitch() => defaultConfig();

  Map<String, Object?> extraFromExisting(AppProviderConfig? existing) =>
      const {};

  Map<String, Object?> extraFromPreset(AppProviderPreset preset) => const {};

  Map<String, Object?> buildConfig(ProviderFormInput input) =>
      Map<String, Object?>.from(input.config);

  Widget buildExtraSection(
    BuildContext context,
    ProviderFormSectionProps props,
  ) => const SizedBox.shrink();
}
