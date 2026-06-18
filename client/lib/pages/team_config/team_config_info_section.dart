import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/identity_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../utils/app_keys.dart';
import '../../services/cli/registry/capabilities/cli_effort_capability.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_provider/cli_effort_picker_field.dart';
import '../../widgets/app_provider/provider_brand_icon.dart';
import '../../widgets/cli/cli_brand_icon.dart';
import '../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import '../home_workspace/project/config/workspace_cli_config_helpers.dart';
import 'team_config_helpers.dart';
import 'team_default_preset_configure_dialog.dart';

class TeamInfoSection extends StatefulWidget {
  const TeamInfoSection({super.key, required this.team, required this.cubit});

  final TeamIdentity team;
  final IdentityCubit cubit;

  @override
  State<TeamInfoSection> createState() => TeamInfoSectionState();
}

class TeamInfoSectionState extends State<TeamInfoSection> {
  late TextEditingController _descCtl;
  late TextEditingController _argsCtl;
  late String _trackedTeamId;

  @override
  void initState() {
    super.initState();
    _descCtl = TextEditingController(text: widget.team.description);
    _argsCtl = TextEditingController(text: widget.team.extraArgs);
    _trackedTeamId = widget.team.id;
  }

  @override
  void didUpdateWidget(covariant TeamInfoSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.team.id != _trackedTeamId) {
      _trackedTeamId = widget.team.id;
      _descCtl.text = widget.team.description;
      _argsCtl.text = widget.team.extraArgs;
    }
    if (widget.team.description != _descCtl.text) {
      _descCtl.text = widget.team.description;
    }
  }

  @override
  void dispose() {
    _descCtl.dispose();
    _argsCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final loopKey = widget.team.loop == null
        ? '__default__'
        : (widget.team.loop! ? 'true' : 'false');
    final showTeamCliRow = widget.team.teamMode != TeamMode.mixed;
    final catalogCli = showTeamCliRow
        ? catalogCliForTeam(context, widget.team.cli)
        : null;
    final showDelegateRow =
        catalogCli == CliTool.claude || catalogCli == CliTool.flashskyai;
    // Stop-hook/bus 仅 mixed 模式接线,故此开关只在 mixed 团队出现。
    final showForceWaitRow = widget.team.teamMode == TeamMode.mixed;
    final showTeamEffort = teamShowsEffortPicker(
      context,
      cli: widget.team.cli,
      placement: EffortPickerPlacement.team,
    );
    final teamEffort = widget.team.effortForCli(widget.team.cli);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsLabeledStackedRow(
                  title: l10n.teamName,
                  body: Text(
                    key: AppKeys.teamNameField,
                    widget.team.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  showDividerBelow: true,
                ),
                SettingsLabeledStackedRow(
                  title: l10n.teamDescription,
                  subtitle: l10n.teamDescriptionHint,
                  body: TextField(
                    controller: _descCtl,
                    maxLines: 3,
                    decoration: const InputDecoration(),
                    onChanged: (v) => widget.cubit.updateSelected(
                      widget.team.copyWith(description: v),
                    ),
                  ),
                  showDividerBelow: true,
                ),
                SettingsLabeledStackedRow(
                  title: l10n.teamLoop,
                  subtitle: l10n.teamLoopSubtitle,
                  body: SettingsCompactDropdown<String>(
                    value: loopKey,
                    entries: [
                      ('__default__', l10n.teamLoopDefault),
                      ('true', l10n.teamLoopTrue),
                      ('false', l10n.teamLoopFalse),
                    ],
                    onChanged: (value) {
                      final key = value ?? '__default__';
                      final bool? next = key == '__default__'
                          ? null
                          : key == 'true';
                      widget.cubit.updateSelected(
                        widget.team.copyWith(loop: next, updateLoop: true),
                      );
                    },
                  ),
                  showDividerBelow: showTeamCliRow,
                ),
                if (showTeamCliRow)
                  SettingsLabeledStackedRow(
                    title: l10n.teamCliLabel,
                    subtitle: l10n.teamCliLockedSubtitle,
                    body: Row(
                      children: [
                        CliBrandIcon(
                          cli: widget.team.cli,
                          label: teamCliDisplayLabel(
                            context,
                            l10n,
                            widget.team.cli,
                          ),
                          size: 28,
                          borderRadius: 7,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            teamCliDisplayLabel(context, l10n, widget.team.cli),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                          ),
                        ),
                      ],
                    ),
                    showDividerBelow: true,
                  ),
                SettingsLabeledStackedRow(
                  title: l10n.teamExtraArgs,
                  subtitle: l10n.teamExtraArgsHint,
                  body: TextField(
                    controller: _argsCtl,
                    decoration: const InputDecoration(),
                    onChanged: (v) => widget.cubit.updateSelected(
                      widget.team.copyWith(extraArgs: v),
                    ),
                  ),
                  showDividerBelow:
                      showDelegateRow || showTeamEffort || showForceWaitRow,
                ),
                if (showTeamEffort)
                  SettingsLabeledStackedRow(
                    title: l10n.teamEffortLevel,
                    subtitle: l10n.teamEffortLevelSubtitle,
                    body: CliEffortPickerField(
                      cli: widget.team.cli,
                      value: teamEffort,
                      team: widget.team,
                      decoration: AppDropdownDecorations.themed(context),
                      onChanged: (value) => widget.cubit.updateSelected(
                        widget.team.withEffortForCli(widget.team.cli, value),
                      ),
                    ),
                    showDividerBelow: true,
                  ),
                _TeamDefaultPresetRow(
                  team: widget.team,
                  cubit: widget.cubit,
                  showDividerBelow: showDelegateRow || showForceWaitRow,
                ),
                if (showDelegateRow)
                  SettingsLabeledRow(
                    title: l10n.teamLeadDelegateOnlyTitle,
                    subtitle: l10n.teamLeadDelegateOnlySubtitle,
                    trailing: Switch(
                      value: widget.team.forceTeamLeadDelegateMode,
                      onChanged: (value) => widget.cubit.updateSelected(
                        widget.team.copyWith(
                          forceTeamLeadDelegateMode: value,
                          updateForceTeamLeadDelegateMode: true,
                        ),
                      ),
                    ),
                    showDividerBelow: showForceWaitRow,
                  ),
                if (showForceWaitRow)
                  SettingsLabeledRow(
                    title: l10n.teamForceWaitBeforeStopTitle,
                    subtitle: l10n.teamForceWaitBeforeStopSubtitle,
                    trailing: Switch(
                      value: widget.team.forceWaitBeforeStop,
                      onChanged: (value) => widget.cubit.updateSelected(
                        widget.team.copyWith(
                          forceWaitBeforeStop: value,
                          updateForceWaitBeforeStop: true,
                        ),
                      ),
                    ),
                    showDividerBelow: false,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TeamConfigDangerZone(team: widget.team, cubit: widget.cubit),
        ],
      ),
    );
  }
}

class _TeamDefaultPresetRow extends StatelessWidget {
  const _TeamDefaultPresetRow({
    required this.team,
    required this.cubit,
    required this.showDividerBelow,
  });

  final TeamIdentity team;
  final IdentityCubit cubit;
  final bool showDividerBelow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final registry = CliToolRegistryScope.of(context);
    final presets = context.watch<CliPresetsCubit>().state.presets;
    final currentTeam = context.watch<IdentityCubit>().state.teams.firstWhere(
      (t) => t.id == team.id,
      orElse: () => team,
    );
    final catalogCli = currentTeam.cli;
    final activePreset = currentTeam.activePresetId != null
        ? _findPreset(presets, currentTeam.activePresetId!)
        : null;
    final configured = teamLaunchDefaultsConfigured(
      team: currentTeam,
      presets: presets,
      catalogCli: catalogCli,
    );

    AppProviderConfig? selectedProvider;
    var hidesModelPicker = false;
    String configLine;
    CliTool displayCli = catalogCli;
    if (activePreset != null) {
      displayCli = activePreset.cli;
      final providers = context
          .watch<AppProviderCubit>()
          .state
          .providersFor(activePreset.cli)
          .toList(growable: false);
      final prov = activePreset.provider.trim();
      if (prov.isNotEmpty) {
        for (final p in providers) {
          if (p.id == prov) {
            selectedProvider = p;
            break;
          }
        }
      }
      hidesModelPicker = workspaceCliHidesModelPicker(
        registry,
        activePreset.cli,
        selectedProvider,
      );
      configLine = teamPresetConfigLine(
        l10n: l10n,
        registry: registry,
        preset: activePreset,
        provider: selectedProvider,
        hidesModelPicker: hidesModelPicker,
      );
    } else {
      final providers = context
          .watch<AppProviderCubit>()
          .state
          .providersFor(catalogCli)
          .toList(growable: false);
      final prov = currentTeam.providerForCli(catalogCli);
      if (prov.isNotEmpty) {
        for (final p in providers) {
          if (p.id == prov) {
            selectedProvider = p;
            break;
          }
        }
      }
      hidesModelPicker = workspaceCliHidesModelPicker(
        registry,
        catalogCli,
        selectedProvider,
      );
      configLine = teamCustomLaunchConfigLine(
        l10n: l10n,
        registry: registry,
        team: currentTeam,
        catalogCli: catalogCli,
        provider: selectedProvider,
        hidesModelPicker: hidesModelPicker,
      );
    }

    final catalogDef = registry.tryGet(displayCli);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              configured &&
                      selectedProvider != null &&
                      selectedProvider.icon.isNotEmpty
                  ? ProviderBrandIcon.fromConfig(
                      selectedProvider,
                      size: 40,
                      borderRadius: 10,
                    )
                  : catalogDef != null
                  ? CliBrandIcon(
                      cli: displayCli,
                      definition: catalogDef,
                      label: cliDisplayName(catalogDef, l10n),
                      size: 40,
                      borderRadius: 10,
                    )
                  : _TeamPresetIcon(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            l10n.teamDefaultPresetLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: styles.prominent.copyWith(
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SettingsConfiguredBadge(configured: configured),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (!configured)
                      Text(
                        l10n.teamDefaultPresetSubtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: styles.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    if (configured) ...[
                      const SizedBox(height: 2),
                      Text(
                        configLine,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: styles.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => openTeamDefaultPresetConfigureDialog(
                  context,
                  team: currentTeam,
                  cubit: cubit,
                ),
                icon: Icon(Icons.tune, size: context.appIconSizes.sm),
                label: Text(l10n.workspaceCliConfigure),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDividerBelow)
          Divider(
            height: 1,
            thickness: 1,
            color: cs.outlineVariant.withValues(alpha: 0.5),
          ),
      ],
    );
  }
}

class _TeamPresetIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Icon(Icons.layers_outlined, size: 22, color: cs.primary),
    );
  }
}

CliPreset? _findPreset(List<CliPreset> presets, String id) {
  for (final p in presets) {
    if (p.id == id) return p;
  }
  return null;
}

class TeamConfigDangerZone extends StatelessWidget {
  const TeamConfigDangerZone({
    super.key,
    required this.team,
    required this.cubit,
  });

  final TeamIdentity team;
  final IdentityCubit cubit;

  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDialogHeader(
              title: l10n.deleteTeam,
              onClose: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(height: 16),
            Text(l10n.deleteTeamConfirm(team.name)),
            AppDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.delete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await cubit.deleteSelected();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final errorColor = Theme.of(context).colorScheme.error;
    return SettingsSurfaceCard(
      child: SettingsLabeledStackedRow(
        title: l10n.dangerZone,
        subtitle: l10n.deleteTeamSubtitle,
        body: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: AppKeys.deleteButton,
            onPressed: () => _confirmDelete(context),
            icon: Icon(
              Icons.delete_outline,
              size: context.appIconSizes.md,
              color: errorColor,
            ),
            label: Text(l10n.deleteTeam, style: TextStyle(color: errorColor)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: errorColor.withValues(alpha: 0.4)),
            ),
          ),
        ),
        showDividerBelow: false,
      ),
    );
  }
}
