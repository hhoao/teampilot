import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/app_dialog.dart';

/// Shared delete-team confirmation used by team config and My Teams.
Future<bool> confirmDeleteTeam(BuildContext context, String teamName) async {
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
          Text(l10n.deleteTeamConfirm(teamName)),
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
  return confirmed == true;
}
