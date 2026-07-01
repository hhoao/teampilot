import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/cli/registry/capabilities/cli_effort_capability.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/cli_launch_config/cli_launch_custom_fields.dart';
import '../../widgets/cli_launch_config/member_launch_config_type_field.dart';
import '../../widgets/cli_launch_config/preset_launch_picker_field.dart';
import '../../widgets/cli_launch_config/team_launch_config_kind.dart';
import '../../widgets/cli_launch_config/team_launch_config_type_field.dart';
import '../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import '../home_workspace/workspace/config/cli_presets_manage_dialog.dart';
import 'team_config_helpers.dart';

Future<void> openTeamDefaultPresetConfigureDialog(
  BuildContext context, {
  required TeamProfile team,
  required LaunchProfileCubit cubit,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => TeamDefaultPresetConfigureDialog(team: team, cubit: cubit),
  );
}

class TeamDefaultPresetConfigureDialog extends StatefulWidget {
  const TeamDefaultPresetConfigureDialog({
    required this.team,
    required this.cubit,
    super.key,
  });

  final TeamProfile team;
  final LaunchProfileCubit cubit;

  @override
  State<TeamDefaultPresetConfigureDialog> createState() =>
      _TeamDefaultPresetConfigureDialogState();
}

class _TeamDefaultPresetConfigureDialogState
    extends State<TeamDefaultPresetConfigureDialog> {
  late CliTool _catalogCli;
  late String _providerId;
  late String _modelId;
  late String _effortId;
  late TeamLaunchConfigKind _configKind;

  @override
  void initState() {
    super.initState();
    _catalogCli = widget.team.cli;
    _providerId = widget.team.providerForCli(_catalogCli);
    _modelId = widget.team.modelForCli(_catalogCli);
    _effortId = widget.team.effortForCli(_catalogCli);
    _configKind = teamLaunchConfigKind(widget.team);
  }

  void _applyCatalogCliChange(CliTool cli) {
    final team = _currentTeam;
    setState(() {
      _catalogCli = cli;
      _providerId = team.providerForCli(cli);
      _modelId = team.modelForCli(cli);
      _effortId = team.effortForCli(cli);
    });
  }

  TeamProfile get _currentTeam {
    return widget.cubit.state.teams.firstWhere(
      (t) => t.id == widget.team.id,
      orElse: () => widget.team,
    );
  }

  void _applyConfigKind(TeamLaunchConfigKind kind) {
    setState(() => _configKind = kind);
    if (kind == TeamLaunchConfigKind.custom) {
      widget.cubit.setTeamActivePreset(null);
      final team = _currentTeam;
      setState(() {
        _providerId = team.providerForCli(_catalogCli);
        _modelId = team.modelForCli(_catalogCli);
        _effortId = team.effortForCli(_catalogCli);
      });
    }
  }

  void _applyPresetChoice(String token) {
    CliTool? syncCli;
    for (final preset in context.read<CliPresetsCubit>().state.presets) {
      if (preset.id == token) {
        syncCli = preset.cli;
        break;
      }
    }
    widget.cubit.setTeamActivePreset(token, syncCli: syncCli);
    setState(() {
      _configKind = TeamLaunchConfigKind.preset;
      if (syncCli != null) _catalogCli = syncCli;
    });
  }

  void _save() {
    if (_configKind == TeamLaunchConfigKind.custom) {
      widget.cubit.updateTeamCustomLaunch(
        catalogCli: _catalogCli,
        defaultCli: _currentTeam.teamMode == TeamMode.mixed
            ? _catalogCli
            : null,
        providerId: _providerId,
        model: _modelId,
        effort: _effortId,
      );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = CliToolRegistryScope.of(context);
    final dropdownDeco = AppDropdownDecorations.themed(context);
    context.watch<LaunchProfileCubit>();
    final team = _currentTeam;
    final allPresets = context.watch<CliPresetsCubit>().state.presets;
    final eligiblePresetList = teamPresetPickerItems(
      team: team,
      allPresets: allPresets,
      catalogCli: _catalogCli,
    );
    final isCustom = _configKind == TeamLaunchConfigKind.custom;
    final presetDropdownItems = presetLaunchDropdownItems(
      mode: PresetLaunchPickerMode.presetOnly,
      eligiblePresets: eligiblePresetList,
    );
    final presetToken = teamLaunchPresetToken(team);
    final effectivePresetToken = presetDropdownItems.contains(presetToken)
        ? presetToken
        : (presetDropdownItems.isNotEmpty ? presetDropdownItems.first : '');
    final providers = context
        .watch<AppProviderCubit>()
        .state
        .providersFor(_catalogCli)
        .toList(growable: false);
    final mixed = team.teamMode == TeamMode.mixed;
    final cliItems = mixed
        ? registry.launchable.map((d) => d.id).toList(growable: false)
        : <CliTool>[];
    final providerState = context.watch<AppProviderCubit>().state;

    return AppDialog(
      maxWidth: 680,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.teamDefaultPresetLabel),
          const SizedBox(height: 16),
          SettingsSurfaceCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeamLaunchConfigTypeField(
                  currentKind: _configKind,
                  decoration: dropdownDeco,
                  showDividerBelow: isCustom,
                  onChanged: _applyConfigKind,
                ),
                if (_configKind == TeamLaunchConfigKind.preset &&
                    presetDropdownItems.isNotEmpty)
                  MemberLaunchPresetField(
                    items: presetDropdownItems,
                    currentToken: effectivePresetToken,
                    eligiblePresets: eligiblePresetList,
                    registry: registry,
                    providerState: providerState,
                    decoration: dropdownDeco,
                    onChanged: _applyPresetChoice,
                  ),
                if (isCustom)
                  CliLaunchCustomFields(
                    catalogCli: _catalogCli,
                    providers: providers,
                    providerId: _providerId,
                    modelId: _modelId,
                    effortId: _effortId,
                    registry: registry,
                    cliFieldKind: mixed
                        ? CliLaunchCliFieldKind.mixedTeam
                        : CliLaunchCliFieldKind.hidden,
                    cliItems: cliItems,
                    cliSubtitle: mixed
                        ? l10n.teamDefaultCliMixedSubtitle
                        : null,
                    onCliChanged: _applyCatalogCliChange,
                    team: team,
                    effortContext: CliLaunchEffortContext.team,
                    effortSubtitle: l10n.teamDefaultDialogEffortSubtitle,
                    dropdownKeyPrefix: 'team-launch',
                    decoration: dropdownDeco,
                    onProviderChanged: (value) => setState(() {
                      _providerId = value;
                      _modelId = '';
                      _effortId = '';
                    }),
                    onModelChanged: (value) => setState(() {
                      _modelId = value.trim();
                      if (!teamShowsEffortPicker(
                        context,
                        cli: _catalogCli,
                        placement: EffortPickerPlacement.team,
                        model: _modelId,
                      )) {
                        _effortId = '';
                      }
                    }),
                    onEffortChanged: (value) =>
                        setState(() => _effortId = value.trim()),
                  ),
              ],
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
                      lockCli: team.teamMode == TeamMode.native
                          ? team.cli
                          : null,
                    ),
                  );
                },
                child: Text(l10n.teamDefaultPresetManage),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              if (isCustom)
                FilledButton(
                  onPressed: _providerId.trim().isEmpty ? null : _save,
                  child: Text(l10n.save),
                )
              else
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.save),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
