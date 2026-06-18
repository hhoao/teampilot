import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/launch_identity.dart';
import '../../services/storage/identity_provisioner.dart';
import '../../widgets/app_dialog.dart';

/// One selectable workspace identity in the launch dialog.
class LaunchProjectIdentityOption {
  const LaunchProjectIdentityOption({
    required this.id,
    required this.name,
    required this.isTeam,
  });

  final String id;
  final String name;
  final bool isTeam;
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
  required List<LaunchProjectIdentityOption> identities,
  LaunchIdentity? preselected,
}) {
  return showDialog<LaunchProjectChoice>(
    context: context,
    builder: (_) => _LaunchProjectDialog(
      projectName: projectName,
      identities: identities,
      preselected: preselected,
    ),
  );
}

class _LaunchProjectDialog extends StatefulWidget {
  const _LaunchProjectDialog({
    required this.projectName,
    required this.identities,
    this.preselected,
  });

  final String projectName;
  final List<LaunchProjectIdentityOption> identities;
  final LaunchIdentity? preselected;

  @override
  State<_LaunchProjectDialog> createState() => _LaunchProjectDialogState();
}

class _LaunchProjectDialogState extends State<_LaunchProjectDialog> {
  late LaunchIdentity _selected = widget.preselected ??
      const LaunchIdentity(IdentityProvisioner.defaultPersonalId);
  bool _remember = false;

  void _choose(LaunchIdentity identity) {
    setState(() => _selected = identity);
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
