import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import '../ssh_profiles/ssh_profiles_section.dart';

class SshProfilesConfigWorkspace extends StatelessWidget {
  const SshProfilesConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) ...[
          WorkspaceSectionHeading(
            title: l10n.sshProfilesPageTitle,
            subtitle: l10n.sshProfilesPageSubtitle,
          ),
          const SizedBox(height: 16),
        ],
        const Expanded(
          child: SingleChildScrollView(child: SshProfilesSection()),
        ),
      ],
    );
  }
}
