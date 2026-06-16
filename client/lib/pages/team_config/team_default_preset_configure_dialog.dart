import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/team_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/cli/registry/capabilities/cli_effort_capability.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_provider/brand_dropdown_rows.dart';
import '../../widgets/app_provider/cli_effort_picker_field.dart';
import '../../widgets/app_provider/provider_model_picker_field.dart';
import '../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../widgets/dropdown/app_dropdown_field.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import '../home_workspace/project/config/cli_presets_manage_dialog.dart';
import '../home_workspace/project/config/project_cli_config_helpers.dart';
import 'team_config_helpers.dart';

Future<void> openTeamDefaultPresetConfigureDialog(
  BuildContext context, {
  required TeamConfig team,
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

  final TeamConfig team;
  final TeamCubit cubit;

  @override
  State<TeamDefaultPresetConfigureDialog> createState() =>
      _TeamDefaultPresetConfigureDialogState();
}

const _presetCustomToken = '__custom__';
const _launchDropdownMinWidth = 180.0;

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

  TeamConfig get _currentTeam {
    return widget.cubit.state.teams.firstWhere(
      (t) => t.id == widget.team.id,
      orElse: () => widget.team,
    );
  }

  void _applyPresetChoice(String token) {
    if (token == _presetCustomToken) {
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

  AppProviderConfig? _selectedProvider(Iterable<AppProviderConfig> providers) {
    for (final provider in providers) {
      if (provider.id == _providerId) return provider;
    }
    return null;
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
    final currentPresetToken = team.activePresetId ?? _presetCustomToken;

    final providers = context
        .watch<AppProviderCubit>()
        .state
        .providersFor(_catalogCli)
        .toList(growable: false);
    final providerIds = providers.map((p) => p.id).toList()..sort();
    if (_providerId.isNotEmpty && !providerIds.contains(_providerId)) {
      providerIds.add(_providerId);
    }
    final providerLabels = {
      for (final provider in providers) provider.id: provider.name,
      if (_providerId.isNotEmpty &&
          !providers.any((p) => p.id == _providerId))
        _providerId: _providerId,
    };
    final selectedProvider = _selectedProvider(providers);
    final hideModelPicker = projectCliHidesModelPicker(
      registry,
      _catalogCli,
      selectedProvider,
    );
    final showEffortPicker = teamShowsEffortPicker(
      context,
      cli: _catalogCli,
      placement: EffortPickerPlacement.team,
      model: _modelId,
    );
    final mixed = team.teamMode == TeamMode.mixed;
    final cliItems = mixed
        ? registry.launchable.map((d) => d.id).toList(growable: false)
        : <CliTool>[];
    final presetDropdownItems = <String>[
      ...eligiblePresetList.map((p) => p.id),
      _presetCustomToken,
    ];

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
                SettingsLabeledRow(
                  title: l10n.memberPresetLabel,
                  trailing: _launchDropdown(
                    AppDropdownField<String>(
                      items: presetDropdownItems,
                      initialItem: currentPresetToken,
                      hintText: l10n.memberPresetSelectPreset,
                      decoration: dropdownDeco,
                      itemLabel: (value) {
                        if (value == _presetCustomToken) {
                          return l10n.memberPresetCustom;
                        }
                        for (final preset in eligiblePresetList) {
                          if (preset.id == value) return preset.name;
                        }
                        return value;
                      },
                      listItemBuilder: (ctx, value) => _presetDropdownItem(
                        ctx,
                        value,
                        eligiblePresetList,
                        l10n,
                        registry,
                        context.watch<AppProviderCubit>().state,
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        _applyPresetChoice(value);
                      },
                    ),
                  ),
                  showDividerBelow: true,
                ),
                if (!isPresetActive) ...[
                  if (mixed)
                    SettingsLabeledRow(
                      title: l10n.teamCliLabel,
                      subtitle: l10n.teamDefaultCliMixedSubtitle,
                      trailing: _launchDropdown(
                        AppDropdownField<CliTool>(
                          items: cliItems,
                          initialItem: _catalogCli,
                          decoration: dropdownDeco,
                          itemLabel: (cli) {
                            final def = registry.tryGet(cli);
                            return def == null
                                ? cli.value
                                : cliDisplayName(def, l10n);
                          },
                          onChanged: (value) {
                            if (value == null || value == _catalogCli) return;
                            _applyCatalogCliChange(value);
                          },
                          itemBuilder: (ctx, cli) {
                            final def = registry.tryGet(cli);
                            return cliDropdownRow(
                              ctx,
                              cli: cli,
                              label: def == null
                                  ? cli.value
                                  : cliDisplayName(def, l10n),
                              registry: registry,
                            );
                          },
                        ),
                      ),
                      showDividerBelow: true,
                    ),
                  SettingsLabeledRow(
                    title: l10n.provider,
                    trailing: _launchDropdown(
                      AppDropdownField<String>(
                        key: ValueKey(
                          'team-launch-provider-$_catalogCli-$_providerId',
                        ),
                        items: providerIds,
                        initialItem: _providerId.isEmpty ? null : _providerId,
                        hintText: l10n.selectProvider,
                        decoration: dropdownDeco,
                        onChanged: (value) {
                          setState(() {
                            _providerId = value ?? '';
                            _modelId = '';
                            _effortId = '';
                          });
                        },
                        itemBuilder: providerDropdownItemBuilder(
                          providers: providers,
                          labelFor: (value) => providerLabels[value] ?? value,
                        ),
                      ),
                    ),
                    showDividerBelow: !hideModelPicker || showEffortPicker,
                  ),
                  if (!hideModelPicker)
                    SettingsLabeledRow(
                      title: l10n.model,
                      trailing: _launchDropdown(
                        ProviderModelPickerField(
                          key: ValueKey(
                            'team-launch-model-$_providerId-$_modelId',
                          ),
                          cli: _catalogCli,
                          providerId: _providerId,
                          provider: selectedProvider,
                          value: _modelId,
                          hintText: l10n.selectModel,
                          decoration: dropdownDeco,
                          onChanged: (value) => setState(() {
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
                        ),
                      ),
                      showDividerBelow: showEffortPicker,
                    ),
                  if (showEffortPicker)
                    SettingsLabeledRow(
                      title: l10n.teamEffortLevel,
                      subtitle: l10n.teamDefaultDialogEffortSubtitle,
                      trailing: _launchDropdown(
                        CliEffortPickerField(
                          key: ValueKey(
                            'team-launch-effort-$_providerId-$_modelId-$_effortId',
                          ),
                          cli: _catalogCli,
                          value: _effortId,
                          team: team,
                          provider: selectedProvider,
                          model: _modelId,
                          decoration: dropdownDeco,
                          onChanged: (value) =>
                              setState(() => _effortId = value.trim()),
                        ),
                      ),
                      showDividerBelow: false,
                    ),
                ],
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

  Widget _presetDropdownItem(
    BuildContext ctx,
    String value,
    List<CliPreset> eligible,
    AppLocalizations l10n,
    CliToolRegistry registry,
    AppProviderState providerState,
  ) {
    if (value == _presetCustomToken) {
      return Text(
        l10n.memberPresetCustom,
        style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface),
      );
    }
    for (final preset in eligible) {
      if (preset.id == value) {
        final provider = providerConfigForPreset(
          providers: providerState.providersFor(preset.cli),
          preset: preset,
        );
        final subtitle = presetPickerSubtitle(
          registry: registry,
          l10n: l10n,
          preset: preset,
          provider: provider,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(preset.name),
            Text(
              subtitle,
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      }
    }
    return Text(value);
  }
}

Widget _launchDropdown(Widget child) {
  return ConstrainedBox(
    constraints: const BoxConstraints(minWidth: _launchDropdownMinWidth),
    child: child,
  );
}
