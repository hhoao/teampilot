import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/settings/workspace_pane_header.dart';
import '../ssh_profiles_page.dart';

/// Remote-authoritative SSH server catalog for the current home plane.
///
/// Shows what the machine behind the current home has configured (its own
/// `remote-targets.json` merged with the synced projection). The list is
/// read-only and offers no connect action: managing connections belongs to the
/// device-local "Remote connections" section.
class SshProfilesConfigWorkspace extends StatelessWidget {
  const SshProfilesConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading)
          WorkspacePaneHeader(title: context.l10n.sshProfilesPageTitle),
        const Expanded(child: SshServersPage(embedded: true)),
      ],
    );
  }
}
