import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/settings/workspace_pane_header.dart';
import '../ssh_profiles/ssh_profiles_section.dart';

/// Device-local "remote connections" catalog: the always-available settings
/// surface for adding/editing targets, connecting, and switching home.
///
/// Unlike the startup gate's connection page (which shows a status card while
/// the home is down), this section is reachable at all times — including when
/// the SSH home is connected — because connection management lives on the
/// device, not on any remote host.
class RemoteConnectionsConfigSection extends StatelessWidget {
  const RemoteConnectionsConfigSection({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading)
          WorkspacePaneHeader(title: l10n.remoteConnectionsTitle),
        const Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: SshProfilesSection(showRemoteConfig: false),
          ),
        ),
      ],
    );
  }
}
