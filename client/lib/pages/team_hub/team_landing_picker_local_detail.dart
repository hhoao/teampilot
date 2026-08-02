import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import 'team_hub_cards.dart';
import 'team_hub_visuals.dart';

/// Local-team detail pane inside the landing picker dialog.
class TeamLandingPickerLocalDetail extends StatelessWidget {
  const TeamLandingPickerLocalDetail({
    required this.team,
    required this.confirming,
    required this.onBack,
    required this.onConfirm,
    this.inset = 12,
    super.key,
  });

  final TeamProfile team;
  final bool confirming;
  final VoidCallback onBack;
  final VoidCallback onConfirm;
  final double inset;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.all(inset),
      child: TeamHubWorkspaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 18, 0),
              child: TeamHubCardHeader(
                title: team.name,
                leading: TpIconButton(
                  icon: Icons.arrow_back_rounded,
                  size: TpIconButton.chromeAlignedSize(context),
                  onTap: onBack,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      TeamMonogram(
                        seed: team.id,
                        label: team.name,
                        size: 52,
                        radius: 14,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: TeamStatChip(
                          icon: Icons.people_alt_outlined,
                          label: l10n.myTeamsMemberCount(team.roster.length),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: confirming ? null : onConfirm,
                        child: Text(l10n.teamHubConfirmSelection),
                      ),
                    ],
                  ),
                  if (team.description.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(team.description, style: styles.mdRelaxed),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
