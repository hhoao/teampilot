import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../cubits/team_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/team_config.dart';
import '../../utils/app_keys.dart';
import '../../services/cli/registry/capabilities/cli_effort_capability.dart';
import '../../widgets/app_provider/cli_effort_picker_field.dart';
import '../../widgets/app_provider/team_tool_provider_selectors.dart';
import '../../widgets/cli/cli_brand_icon.dart';
import '../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import 'team_config_helpers.dart';

class TeamInfoSection extends StatefulWidget {
  const TeamInfoSection({super.key, required this.team, required this.cubit});

  final TeamConfig team;
  final TeamCubit cubit;

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
    final catalogCli = catalogCliForTeam(context, widget.team.cli);
    final showDelegateRow =
        catalogCli == CliTool.claude ||
        catalogCli == CliTool.flashskyai;
    final showToolProviders = catalogCli == CliTool.claude;
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
                  showDividerBelow: true,
                ),
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
                      showDelegateRow || showToolProviders || showTeamEffort,
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
                    showDividerBelow: showDelegateRow || showToolProviders,
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
                    showDividerBelow: showToolProviders,
                  ),
                if (showToolProviders)
                  TeamToolProviderSelectors(
                    team: widget.team,
                    onChanged: widget.cubit.updateSelected,
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

class TeamConfigDangerZone extends StatelessWidget {
  const TeamConfigDangerZone({super.key, required this.team, required this.cubit});

  final TeamConfig team;
  final TeamCubit cubit;

  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteTeam),
        content: Text(l10n.deleteTeamConfirm(team.name)),
        actions: [
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
            icon: Icon(Icons.delete_outline, size: AppIconSizes.md, color: errorColor),
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
