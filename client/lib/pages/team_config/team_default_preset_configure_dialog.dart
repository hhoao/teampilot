import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/team_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/team_config.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/cli/registry/capabilities/cli_effort_capability.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/cli_launch_config/cli_launch_config_tokens.dart';
import '../../widgets/cli_launch_config/cli_launch_custom_fields.dart';
import '../../widgets/cli_launch_config/preset_launch_picker_field.dart';
import '../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import '../home_workspace/project/config/cli_presets_manage_dialog.dart';
import 'team_config_helpers.dart';

Future<void> openTeamDefaultPresetConfigureDialog(
  BuildContext context, {
  required TeamIdentity team,
  required TeamCubit cubit,
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

  final TeamIdentity team;
  final TeamCubit cubit;

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

  @override
  void initState() {
    super.initState();
    _catalogCli = widget.team.cli;
    _providerId = widget.team.providerForCli(_catalogCli);
    _modelId = widget.team.modelForCli(_catalogCli);
    _effortId = widget.team.effortForCli(_catalogCli);
  }

  bool get _isPresetActive => _currentTeam.activePresetId != null;

  void _applyCatalogCliChange(CliTool cli) {
    final team = _currentTeam;
    setState(() {
      _catalogCli = cli;
      _providerId = team.providerForCli(cli);
      _modelId = team.modelForCli(cli);
      _effortId = team.effortForCli(cli);
    });
  }

  TeamIdentity get _currentTeam {
    return widget.cubit.state.teams.firstWhere(
      (t) => t.id == widget.team.id,
      orElse: () => widget.team,
    );
  }

  void _applyPresetChoice(String token) {
    if (token == CliLaunchConfigTokens.presetCustom) {
      widget.cubit.setTeamActivePreset(null);
      final team = _currentTeam;
      setState(() {
        _providerId = team.providerForCli(_catalogCli);
        _modelId = team.modelForCli(_catalogCli);
        _effortId = team.effortForCli(_catalogCli);
      });
      return;
    }
    widget.cubit.setTeamActivePreset(token);
  }

  void _save() {
    if (!_isPresetActive) {
      widget.cubit.updateTeamCustomLaunch(
        catalogCli: _catalogCli,
        defaultCli:
            _currentTeam.teamMode == TeamMode.mixed ? _catalogCli : null,
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
    context.watch<TeamCubit>();
    final team = _currentTeam;
    final allPresets = context.watch<CliPresetsCubit>().state.presets;
    final eligiblePresetList = teamPresetPickerItems(
      team: team,
      allPresets: allPresets,
      catalogCli: _catalogCli,
    );
    final isPresetActive = team.activePresetId != null;
    final currentPresetToken =
        team.activePresetId ?? CliLaunchConfigTokens.presetCustom;
    final presetDropdownItems = presetLaunchDropdownItems(
      mode: PresetLaunchPickerMode.customOnly,
      eligiblePresets: eligiblePresetList,
    );
    final providers = context
        .watch<AppProviderCubit>()
        .state
        .providersFor(_catalogCli)
        .toList(growable: false);
    final mixed = team.teamMode == TeamMode.mixed;
    final cliItems = mixed
        ? registry.launchable.map((d) => d.id).toList(growable: false)
        : <CliTool>[];

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
                PresetLaunchPickerField(
                  mode: PresetLaunchPickerMode.customOnly,
                  items: presetDropdownItems,
                  currentToken: currentPresetToken,
                  eligiblePresets: eligiblePresetList,
                  registry: registry,
                  providerState: context.watch<AppProviderCubit>().state,
                  decoration: dropdownDeco,
                  onChanged: _applyPresetChoice,
                ),
                if (!isPresetActive)
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
                    cliSubtitle: mixed ? l10n.teamDefaultCliMixedSubtitle : null,
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
              if (!isPresetActive)
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
