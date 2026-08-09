import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../theme/workspace_surface_layers.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import 'team_hub_cards.dart';
import 'team_hub_visuals.dart';

/// Compact local-team card for the landing picker catalog grid.
class TeamLandingPickerLocalCard extends StatefulWidget {
  const TeamLandingPickerLocalCard({
    required this.team,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final TeamProfile team;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<TeamLandingPickerLocalCard> createState() =>
      _TeamLandingPickerLocalCardState();
}

class _TeamLandingPickerLocalCardState
    extends State<TeamLandingPickerLocalCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final l10n = context.l10n;
    final team = widget.team;
    final accent = teamAccentColor(team.id, Theme.of(context).brightness);
    final borderColor = widget.selected
        ? cs.primary
        : _hovered
        ? accent.withValues(alpha: 0.55)
        : cs.outlineVariant;

    return TpHover(
      onTap: widget.onTap,
      backgroundColor: Colors.transparent,
      hoverColor: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      onHoverChanged: (hovered) => setState(() => _hovered = hovered),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: widget.selected
              ? cs.primary.withValues(alpha: 0.06)
              : cs.workspaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: widget.selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TeamMonogram(seed: team.id, label: team.name),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        team.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: styles.mdSemiboldColored(cs.onSurface),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Text(
                    team.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: styles.mutedMd,
                  ),
                ),
                TeamStatChip(
                  icon: Icons.people_alt_outlined,
                  label: l10n.myTeamsMemberCount(team.roster.length),
                ),
              ],
            ),
          ),
        ),
    );
  }
}
