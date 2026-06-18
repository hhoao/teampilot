import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/launch_identity.dart';
import '../../services/storage/identity_provisioner.dart';
import '../../widgets/app_dialog.dart';

/// One selectable workspace identity in the launch dialog.
class LaunchWorkspaceIdentityOption {
  const LaunchWorkspaceIdentityOption({
    required this.id,
    required this.name,
    required this.isTeam,
  });

  final String id;
  final String name;
  final bool isTeam;
}

/// Result of the launch dialog.
class LaunchWorkspaceChoice {
  const LaunchWorkspaceChoice({required this.identity, required this.remember});
  final LaunchIdentity identity;
  final bool remember;
}

/// Asks which identity to open a workspace as. Returns null on cancel.
Future<LaunchWorkspaceChoice?> showHomeLaunchWorkspaceDialog(
  BuildContext context, {
  required String workspaceName,
  required List<LaunchWorkspaceIdentityOption> identities,
  LaunchIdentity? preselected,
}) {
  return showDialog<LaunchWorkspaceChoice>(
    context: context,
    builder: (_) => _LaunchWorkspaceDialog(
      workspaceName: workspaceName,
      identities: identities,
      preselected: preselected,
    ),
  );
}

class _LaunchWorkspaceDialog extends StatefulWidget {
  const _LaunchWorkspaceDialog({
    required this.workspaceName,
    required this.identities,
    this.preselected,
  });

  final String workspaceName;
  final List<LaunchWorkspaceIdentityOption> identities;
  final LaunchIdentity? preselected;

  @override
  State<_LaunchWorkspaceDialog> createState() => _LaunchWorkspaceDialogState();
}

class _LaunchWorkspaceDialogState extends State<_LaunchWorkspaceDialog> {
  late LaunchIdentity _selected = widget.preselected ??
      const LaunchIdentity(IdentityProvisioner.defaultPersonalId);
  bool _remember = false;

  void _choose(LaunchIdentity identity) {
    setState(() => _selected = identity);
    Navigator.of(context).pop(
      LaunchWorkspaceChoice(identity: identity, remember: _remember),
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
          AppDialogHeader(title: l10n.homeWorkspaceLaunchWorkspaceTitle),
          const SizedBox(height: 12),
          for (final opt in widget.identities)
            ListTile(
              leading: Icon(
                opt.isTeam
                    ? Icons.groups_2_outlined
                    : Icons.person_outline_rounded,
              ),
              title: Text(opt.name),
              selected: _selected == LaunchIdentity(opt.id),
              onTap: () => _choose(LaunchIdentity(opt.id)),
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
