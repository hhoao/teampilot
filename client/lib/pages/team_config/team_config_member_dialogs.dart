import 'package:flutter/material.dart';

import '../../cubits/team_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../widgets/app_dialog.dart';

Future<void> confirmDeleteTeamMember(
  BuildContext context,
  TeamCubit cubit,
  TeamMemberConfig member,
  AppLocalizations l10n,
) async {
  final name = member.name.trim().isEmpty ? l10n.memberName : member.name;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AppDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(
            title: l10n.delete,
            onClose: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(height: 16),
          Text(name),
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
    await cubit.deleteMember(member.id);
  }
}
