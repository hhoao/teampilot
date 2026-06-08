import 'package:flutter/widgets.dart';

import '../../models/app_provider_config.dart';
import '../cli/registry/capabilities/provider_form_capability.dart';

/// Default form behavior for CLIs without advanced provider fields.
abstract base class PassthroughProviderFormCapability
    implements ProviderFormCapability {
  const PassthroughProviderFormCapability();

  @override
  String normalizeApiKeyField(String? raw) {
    final value = raw?.trim() ?? '';
    return value.isEmpty ? defaultApiKeyField() : value;
  }

  @override
  Map<String, Object?> configForCliSwitch() => defaultConfig();

  @override
  Map<String, Object?> extraFromExisting(AppProviderConfig? existing) =>
      const {};

  @override
  Map<String, Object?> extraFromPreset(AppProviderPreset preset) => const {};

  @override
  Map<String, Object?> buildConfig(ProviderFormInput input) =>
      Map<String, Object?>.from(input.config);

  @override
  Widget buildExtraSection(
    BuildContext context,
    ProviderFormSectionProps props,
  ) =>
      const SizedBox.shrink();
}
