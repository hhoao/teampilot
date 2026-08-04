import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/cli/registry/capabilities/cli_effort_capability.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../widgets/cli_launch_config/cli_launch_custom_fields.dart';
import '../../widgets/cli_launch_config/member_launch_config_type_field.dart';
import '../../widgets/cli_launch_config/preset_launch_picker_field.dart';
import '../../widgets/cli_launch_config/team_launch_config_kind.dart';
import '../../widgets/cli_launch_config/team_launch_config_type_field.dart';
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
  late String _presetToken;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _catalogCli = widget.team.cli;
    _providerId = widget.team.providerForCli(_catalogCli);
    _modelId = widget.team.modelForCli(_catalogCli);
    _effortId = widget.team.effortForCli(_catalogCli);
    _configKind = teamLaunchConfigKind(widget.team);
    _presetToken = teamLaunchPresetToken(widget.team);
  }

  TeamProfile get _baselineTeam => widget.team;

  void _applyCatalogCliChange(CliTool cli) {
    setState(() {
      _catalogCli = cli;
      _providerId = _baselineTeam.providerForCli(cli);
      _modelId = _baselineTeam.modelForCli(cli);
      _effortId = _baselineTeam.effortForCli(cli);
    });
  }

  void _applyConfigKind(TeamLaunchConfigKind kind) {
    setState(() {
      _configKind = kind;
      if (kind == TeamLaunchConfigKind.custom) {
        _providerId = _baselineTeam.providerForCli(_catalogCli);
        _modelId = _baselineTeam.modelForCli(_catalogCli);
        _effortId = _baselineTeam.effortForCli(_catalogCli);
      } else if (kind == TeamLaunchConfigKind.preset) {
        _ensurePresetTokenSelected();
      }
    });
  }

  void _ensurePresetTokenSelected() {
    final allPresets = context.read<CliPresetsCubit>().state.presets;
    final eligiblePresetList = teamPresetPickerItems(
      team: _baselineTeam,
      allPresets: allPresets,
    );
    final presetDropdownItems = presetLaunchDropdownItems(
      mode: PresetLaunchPickerMode.presetOnly,
      eligiblePresets: eligiblePresetList,
    );
    _presetToken = effectivePresetLaunchToken(
      currentToken: _presetToken,
      dropdownItems: presetDropdownItems,
    );
    for (final preset in allPresets) {
      if (preset.id == _presetToken) {
        _catalogCli = preset.cli;
        break;
      }
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
    setState(() {
      _configKind = TeamLaunchConfigKind.preset;
      _presetToken = token;
      if (syncCli != null) _catalogCli = syncCli;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (_configKind == TeamLaunchConfigKind.custom) {
        await widget.cubit.updateTeamCustomLaunch(
          catalogCli: _catalogCli,
          defaultCli: _baselineTeam.teamMode == TeamMode.mixed
              ? _catalogCli
              : null,
          providerId: _providerId,
          model: _modelId,
          effort: _effortId,
        );
      } else {
        _ensurePresetTokenSelected();
        if (_presetToken.isEmpty) return;
        CliTool? syncCli;
        for (final preset in context.read<CliPresetsCubit>().state.presets) {
          if (preset.id == _presetToken) {
            syncCli = preset.cli;
            break;
          }
        }
        await widget.cubit.setTeamActivePreset(
          _presetToken,
          syncCli: syncCli,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = CliToolRegistryScope.of(context);
    final dropdownDeco = TpSelectDecorations.themed(context);
    final team = _baselineTeam;
    final allPresets = context.watch<CliPresetsCubit>().state.presets;
    final eligiblePresetList = teamPresetPickerItems(
      team: team,
      allPresets: allPresets,
    );
    final isCustom = _configKind == TeamLaunchConfigKind.custom;
    final presetDropdownItems = presetLaunchDropdownItems(
      mode: PresetLaunchPickerMode.presetOnly,
      eligiblePresets: eligiblePresetList,
    );
    final effectivePresetToken = effectivePresetLaunchToken(
      currentToken: _presetToken,
      dropdownItems: presetDropdownItems,
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
    final providerState = context.watch<AppProviderCubit>().state;

    return TpDialog(
      maxWidth: 680,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.teamDefaultPresetLabel),
          const SizedBox(height: 16),
          TpCard.outlined(
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
          TpDialogActions(
            children: [
              TextButton(
                onPressed: _saving
                    ? null
                    : () {
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
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: _saving
                    ? null
                    : isCustom
                    ? (_providerId.trim().isEmpty
                          ? null
                          : () => unawaited(_save()))
                    : (presetDropdownItems.isEmpty
                          ? null
                          : () => unawaited(_save())),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
