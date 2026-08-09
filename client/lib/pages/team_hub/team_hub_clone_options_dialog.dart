import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_team.dart';
import '../../models/team_config.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../widgets/app_provider/brand_dropdown_rows.dart';

/// Clone-time launch params resolved for a hub team whose manifest omitted them.
class TeamHubCloneOptions {
  const TeamHubCloneOptions({required this.teamMode, required this.cli});

  final TeamMode teamMode;
  final CliTool cli;
}

/// Resolves the effective teamMode/cli for cloning [team].
///
/// Returns immediately when both fields are declared in the manifest. Otherwise
/// shows [TeamHubCloneOptionsDialog] for the undeclared fields and returns the
/// user's picks — or `null` if the user cancelled.
Future<TeamHubCloneOptions?> resolveTeamHubCloneOptions(
  BuildContext context,
  DiscoverableTeam team,
) async {
  if (team.teamModeDeclared && team.cliDeclared) {
    return TeamHubCloneOptions(teamMode: team.teamMode, cli: team.cli);
  }
  return showTpDialog<TeamHubCloneOptions>(
    context: context,
    maxWidth: 520,
    builder: (_) => TeamHubCloneOptionsDialog(team: team),
  );
}

class TeamHubCloneOptionsDialog extends StatefulWidget {
  const TeamHubCloneOptionsDialog({required this.team, super.key});

  final DiscoverableTeam team;

  @override
  State<TeamHubCloneOptionsDialog> createState() =>
      _TeamHubCloneOptionsDialogState();
}

class _TeamHubCloneOptionsDialogState extends State<TeamHubCloneOptionsDialog> {
  late TeamMode _mode;
  late CliTool _cli;

  @override
  void initState() {
    super.initState();
    _mode = widget.team.teamMode;
    _cli = widget.team.cli;
  }

  void _confirm() => Navigator.of(context).pop(
    TeamHubCloneOptions(teamMode: _mode, cli: _cli),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final team = widget.team;
    final registry = CliToolRegistryScope.of(context);
    final clis = registry.nativeTeamLaunchable.toList()
      ..sort((a, b) => a.id.value.compareTo(b.id.value));

    return TpDialog(
      maxWidth: 520,
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.teamHubCloneOptionsTitle),
          const SizedBox(height: 12),
          if (!team.teamModeDeclared) ...[
            _SectionLabel(title: l10n.teamModeLabel),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _OptionCard(
                    title: l10n.teamModeNative,
                    description: l10n.teamModeNativeDescription,
                    selected: _mode == TeamMode.native,
                    onTap: () => setState(() => _mode = TeamMode.native),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _OptionCard(
                    title: l10n.teamModeMixed,
                    description: l10n.teamModeMixedDescription,
                    selected: _mode == TeamMode.mixed,
                    onTap: () => setState(() => _mode = TeamMode.mixed),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (!team.cliDeclared) ...[
            _SectionLabel(title: l10n.teamCliLabel),
            const SizedBox(height: 8),
            TpCompactSelect<CliTool>(
              value: _cli,
              entries: [
                for (final def in clis) (def.id, cliDisplayName(def, l10n)),
              ],
              itemBuilder: cliDropdownItemBuilder(
                registry: registry,
                l10n: l10n,
              ),
              onChanged: (value) {
                if (value != null) setState(() => _cli = value);
              },
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: TpButton(
                  variant: TpButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TpButton(
                  variant: TpButtonVariant.primary,
                  onPressed: _confirm,
                  child: Text(l10n.confirm),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      title,
      style: TpTextStyles.of(context).mdBoldColored(cs.onSurface),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return TpHover(
      onTap: onTap,
      width: double.infinity,
      borderRadius: BorderRadius.circular(10),
      backgroundColor: selected
          ? cs.primary.withValues(alpha: 0.07)
          : cs.surfaceContainerHighest.withValues(alpha: 0.35),
      border: Border.all(
        color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.6),
        width: selected ? 2 : 1,
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 20,
            color: selected ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: styles.mdBoldColored(cs.onSurface)),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: styles.smColored(cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
