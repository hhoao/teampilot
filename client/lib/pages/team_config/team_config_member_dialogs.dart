import 'package:flutter/material.dart';

import '../../cubits/team_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';

Future<void> confirmDeleteTeamMember(
  BuildContext context,
  TeamCubit cubit,
  TeamMemberConfig member,
  AppLocalizations l10n,
) async {
  final name = member.name.trim().isEmpty ? l10n.memberName : member.name;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.delete),
      content: Text(name),
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
    await cubit.deleteMember(member.id);
  }
}
