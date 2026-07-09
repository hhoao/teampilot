import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../utils/launch_profile_display_name.dart';
import '../../widgets/app_dialog.dart';
import '../team_hub/team_hub_visuals.dart';

/// Picks a team to receive an Expert Hub member. Returns the selected [teamId],
/// or `null` when dismissed.
Future<String?> showExpertTeamPickerDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => const ExpertTeamPickerDialog(),
  );
}

class ExpertTeamPickerDialog extends StatelessWidget {
  const ExpertTeamPickerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final teams = context.select<LaunchProfileCubit, List<TeamProfile>>(
      (c) => c.state.teams,
    );

    return AppDialog(
      maxWidth: 480,
      maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      scrollable: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.selectTeam),
          const SizedBox(height: 8),
          for (final team in teams)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: TeamMonogram(
                seed: team.id,
                label: _teamLabel(l10n, team),
                size: 36,
              ),
              title: Text(
                _teamLabel(l10n, team),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.of(context).pop(team.id),
            ),
        ],
      ),
    );
  }

  static String _teamLabel(AppLocalizations l10n, TeamProfile team) {
    return launchProfileDisplayName(l10n, team);
  }
}
