import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/launch_identity.dart';
import '../../widgets/app_dialog.dart';

/// One selectable team in the launch dialog (already sorted by the caller).
class LaunchProjectTeamOption {
  const LaunchProjectTeamOption({required this.id, required this.name});
  final String id;
  final String name;
}

/// Result of the launch dialog.
class LaunchProjectChoice {
  const LaunchProjectChoice({required this.identity, required this.remember});
  final LaunchIdentity identity;
  final bool remember;
}

/// Asks which identity to open a project as. Returns null on cancel.
Future<LaunchProjectChoice?> showHomeWorkspaceLaunchProjectDialog(
  BuildContext context, {
  required String projectName,
  required List<LaunchProjectTeamOption> teams,
  LaunchIdentity? preselected,
}) {
  return showDialog<LaunchProjectChoice>(
    context: context,
    builder: (_) => _LaunchProjectDialog(
      projectName: projectName,
      teams: teams,
      preselected: preselected,
    ),
  );
}

class _LaunchProjectDialog extends StatefulWidget {
  const _LaunchProjectDialog({
    required this.projectName,
    required this.teams,
    this.preselected,
  });

  final String projectName;
  final List<LaunchProjectTeamOption> teams;
  final LaunchIdentity? preselected;

  @override
  State<_LaunchProjectDialog> createState() => _LaunchProjectDialogState();
}

class _LaunchProjectDialogState extends State<_LaunchProjectDialog> {
  late LaunchIdentity _selected =
      widget.preselected ?? LaunchIdentity.personal;
  bool _remember = false;

  void _choose(LaunchIdentity identity) {
    Navigator.of(context).pop(
      LaunchProjectChoice(identity: identity, remember: _remember),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return AppDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.homeWorkspaceLaunchProjectTitle),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.person_outline_rounded),
            title: Text(l10n.homeWorkspaceSimpleMode),
            selected: _selected == LaunchIdentity.personal,
            onTap: () => _choose(LaunchIdentity.personal),
          ),
          for (final team in widget.teams)
            ListTile(
              leading: const Icon(Icons.groups_2_outlined),
              title: Text(team.name),
              selected: _selected == LaunchIdentity.team(team.id),
              onTap: () => _choose(LaunchIdentity.team(team.id)),
            ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? false),
            title: Text(l10n.homeWorkspaceRememberLaunchChoice),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel, style: TextStyle(color: cs.onSurfaceVariant)),
            ),
          ),
        ],
      ),
    );
  }
}
