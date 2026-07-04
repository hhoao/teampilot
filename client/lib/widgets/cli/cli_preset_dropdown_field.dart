import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/cli_presets_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/cli_preset.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../theme/app_text_styles.dart';
import '../dropdown/app_dropdown_decoration.dart';
import '../dropdown/app_dropdown_field.dart';
import 'cli_brand_icon.dart';

/// Dropdown for choosing a global CLI preset (provider/model/CLI bundle).
class CliPresetDropdownField extends StatelessWidget {
  const CliPresetDropdownField({
    required this.selectedPresetId,
    required this.onChanged,
    this.label,
    super.key,
  });

  final String? selectedPresetId;
  final ValueChanged<String?> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final presetsState = context.watch<CliPresetsCubit>().state;

    if (presetsState.status == CliPresetsLoadStatus.loading) {
      return const LinearProgressIndicator(minHeight: 2);
    }

    final presets = presetsState.presets;
    if (presets.isEmpty) {
      return Text(
        l10n.workspaceCliPresetsEmptyHint,
        style: AppTextStyles.of(context).bodySmall,
      );
    }

    final initialId = _resolveInitialId(presets, selectedPresetId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: AppTextStyles.of(
              context,
            ).bodySmall.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
        ],
        AppDropdownField<String>(
          key: ValueKey('cli-preset-dropdown-$initialId'),
          items: presets.map((p) => p.id).toList(growable: false),
          initialItem: initialId,
          decoration: AppDropdownDecorations.themed(context),
          onChanged: onChanged,
          itemBuilder: (context, presetId) {
            final preset = presetsState.presetById(presetId);
            if (preset == null) {
              return Text(presetId, style: AppTextStyles.of(context).bodySmall);
            }
            return _CliPresetDropdownItem(preset: preset);
          },
        ),
      ],
    );
  }

  String _resolveInitialId(List<CliPreset> presets, String? selected) {
    final trimmed = selected?.trim() ?? '';
    if (trimmed.isNotEmpty && presets.any((p) => p.id == trimmed)) {
      return trimmed;
    }
    return presets.first.id;
  }
}

class _CliPresetDropdownItem extends StatelessWidget {
  const _CliPresetDropdownItem({required this.preset});

  final CliPreset preset;

  @override
  Widget build(BuildContext context) {
    final registry = CliToolRegistryScope.of(context);
    final def = registry.tryGet(preset.cli);
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CliBrandIcon(
          cli: preset.cli,
          definition: def,
          size: 22,
          borderRadius: 6,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            preset.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.of(
              context,
            ).prominent.copyWith(color: cs.onSurface),
          ),
        ),
      ],
    );
  }
}
