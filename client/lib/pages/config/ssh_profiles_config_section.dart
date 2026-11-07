import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/settings/workspace_pane_header.dart';
import '../ssh_profiles_page.dart';
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
        if (showHeading) WorkspacePaneHeader(title: l10n.sshProfilesPageTitle),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SshServersPage(),
                ),
              ),
              icon: const Icon(Icons.dns_outlined, size: 18),
              label: Text(l10n.sshServersTitle),
            ),
          ],
        ),
        const Expanded(
          child: SingleChildScrollView(
            child: SshProfilesSection(showRemoteConfig: false),
          ),
        ),
      ],
    );
  }
}
