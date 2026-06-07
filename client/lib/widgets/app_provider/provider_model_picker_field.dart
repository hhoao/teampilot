import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../services/cli/registry/capabilities/provider_model_capability.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../dropdown/app_dropdown_decoration.dart';
import '../dropdown/app_dropdown_field.dart';
import '../dropdown/app_dropdown_with_custom_input.dart';

/// Registry-driven model picker for team members and project CLI defaults.
class ProviderModelPickerField extends StatelessWidget {
  const ProviderModelPickerField({
    required this.cli,
    required this.providerId,
    required this.provider,
    required this.value,
    required this.onChanged,
    this.decoration,
    this.hintText,
    super.key,
  });

  final CliTool cli;
  final String providerId;
  final AppProviderConfig? provider;
  final String value;
  final ValueChanged<String> onChanged;
  final AppDropdownDecoration? decoration;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final capability = CliToolRegistryScope.of(
      context,
    ).capability<ProviderModelCapability>(cli);
    if (capability == null || provider == null) {
      return const SizedBox.shrink();
    }

    final mode = capability.pickerMode(provider!);
    if (mode == ProviderModelPickerMode.hidden) {
      return const SizedBox.shrink();
    }

    final candidates = capability.modelCandidates(
      provider: provider,
      providerId: providerId,
      currentModel: value,
    );
    final deco = decoration ?? AppDropdownDecorations.themed(context);
    final hint = hintText ?? context.l10n.selectModel;

    return switch (mode) {
      ProviderModelPickerMode.catalogDropdown => AppDropdownField<String>(
        key: ValueKey('provider-model-dd-$providerId-${candidates.join("|")}-$value'),
        items: candidates,
        initialItem: value.trim().isEmpty ? null : value.trim(),
        hintText: hint,
        decoration: deco,
        onChanged: (next) => onChanged(next ?? ''),
        itemLabel: (item) => item,
      ),
      ProviderModelPickerMode.catalogWithCustomEntry => AppDropdownWithCustomInput(
        key: ValueKey('provider-model-custom-$providerId'),
        value: value,
        items: candidates,
        hintText: hint,
        decoration: deco,
        onChanged: onChanged,
      ),
      ProviderModelPickerMode.hidden => const SizedBox.shrink(),
    };
  }
}
