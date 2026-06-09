import 'package:flutter/material.dart';

import '../../models/app_provider_config.dart';
import '../../models/team_config.dart';
import '../../services/cli/registry/capabilities/cli_effort_capability.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../dropdown/app_dropdown_decoration.dart';
import '../dropdown/app_dropdown_field.dart';

/// Registry-driven effort picker for team / member / provider forms.
class CliEffortPickerField extends StatelessWidget {
  const CliEffortPickerField({
    required this.cli,
    required this.value,
    required this.onChanged,
    this.team,
    this.member,
    this.provider,
    this.model = '',
    this.decoration,
    this.hintText,
    this.allowInherit = false,
    this.inheritLabel,
    super.key,
  });

  final CliTool cli;
  final String value;
  final ValueChanged<String> onChanged;
  final TeamConfig? team;
  final TeamMemberConfig? member;
  final AppProviderConfig? provider;
  final String model;
  final AppDropdownDecoration? decoration;
  final String? hintText;
  final bool allowInherit;
  final String? inheritLabel;

  @override
  Widget build(BuildContext context) {
    final capability = CliToolRegistryScope.of(
      context,
    ).capability<CliEffortCapability>(cli);
    if (capability == null) return const SizedBox.shrink();

    final resolvedModel = model.trim().isNotEmpty
        ? model.trim()
        : member?.model.trim() ?? provider?.defaultModel.trim() ?? '';
    if (!capability.isApplicable(model: resolvedModel)) {
      return const SizedBox.shrink();
    }

    final candidates = capability.effortCandidates(
      model: resolvedModel,
      provider: provider,
    );
    if (candidates.isEmpty) return const SizedBox.shrink();

    final items = <String>[
      if (allowInherit) '',
      ...candidates,
    ];
    final deco = decoration ?? AppDropdownDecorations.themed(context);
    final current = value.trim();

    return AppDropdownField<String>(
      key: ValueKey(
        'cli-effort-$cli-$resolvedModel-${items.join("|")}-$current',
      ),
      items: items,
      initialItem: current.isEmpty ? (allowInherit ? '' : null) : current,
      hintText: hintText ?? (inheritLabel ?? ''),
      decoration: deco,
      onChanged: (next) => onChanged(next ?? ''),
      itemLabel: (item) {
        if (item.isEmpty) return inheritLabel ?? '';
        return item;
      },
    );
  }
}
