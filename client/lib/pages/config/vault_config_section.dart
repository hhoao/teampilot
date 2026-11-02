import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/settings/workspace_pane_header.dart';
import '../vault/vault_page.dart';

class VaultConfigSection extends StatelessWidget {
  const VaultConfigSection({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) WorkspacePaneHeader(title: context.l10n.vaultPageTitle),
        const Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: VaultPageBody(),
          ),
        ),
      ],
    );
  }
}
