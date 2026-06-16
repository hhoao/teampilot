import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/team_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_dialog.dart';
import '../home_workspace/project/config/cli_presets_manage_dialog.dart';

class TeamPresetPickerDialog extends StatelessWidget {
  const TeamPresetPickerDialog({
    super.key,
    required this.team,
  });

  final TeamConfig team;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = CliToolRegistryScope.of(context);
    final allPresets = context.watch<CliPresetsCubit>().state.presets;
    final eligible = teamEligiblePresets(
      teamCli: team.cli,
      allPresets: allPresets,
    );
    final activeId = team.activePresetId;

    return AppDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.presetPickerTitle),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // None option
                  _PresetListTile(
                    selected: activeId == null,
                    onTap: () {
                      context.read<TeamCubit>().setTeamActivePreset(null);
                      Navigator.of(context).pop();
                    },
                    title: l10n.presetPickerNoneOption,
                  ),
                  if (eligible.isNotEmpty) ...[
                    const Divider(height: 1),
                    ...eligible.map((preset) {
                      final def = registry.tryGet(preset.cli);
                      final cliName =
                          def != null ? cliDisplayName(def, l10n) : preset.cli.value;
                      final parts = <String>[
                        if (preset.provider.isNotEmpty) preset.provider,
                        if (preset.model.isNotEmpty) preset.model,
                        if (preset.effort.isNotEmpty) preset.effort,
                      ];
                      final subtitle =
                          parts.isNotEmpty ? '$cliName · ${parts.join(' · ')}' : cliName;

                      return _PresetListTile(
                        selected: activeId == preset.id,
                        onTap: () {
                          context.read<TeamCubit>().setTeamActivePreset(preset.id);
                          Navigator.of(context).pop();
                        },
                        title: preset.name,
                        subtitle: subtitle,
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  showDialog<void>(
                    context: context,
                    builder: (_) => CliPresetsManageDialog(
                      lockCli: team.teamMode == TeamMode.native ? team.cli : null,
                    ),
                  );
                },
                child: Text(l10n.teamDefaultPresetManage),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PresetListTile extends StatelessWidget {
  const _PresetListTile({
    required this.selected,
    required this.onTap,
    required this.title,
    this.subtitle,
  });

  final bool selected;
  final VoidCallback onTap;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      selected: selected,
      onTap: onTap,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(title, style: AppTextStyles.of(context).prominent),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: AppTextStyles.of(context).bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : null,
    );
  }
}
