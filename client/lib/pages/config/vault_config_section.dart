import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/runtime_target.dart';
import '../../services/storage/home_storage.dart';
import '../../widgets/settings/workspace_pane_header.dart';
import '../vault/vault_page.dart';

class VaultConfigSection extends StatelessWidget {
  const VaultConfigSection({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Business credentials live on the home plane; show an explicit hint when
    // the remote host is not connected so an empty/short list is not mistaken
    // for lost data.
    HomeStorage? storage;
    try {
      storage = context.read<HomeStorage>();
    } on Object {
      storage = null;
    }
    // Only an SSH home that fell back to the native plane is "offline". A
    // genuinely local home keeps business credentials on that local plane.
    final homeOffline =
        storage != null &&
        storage.context.target.kind == RuntimeKind.ssh &&
        !storage.fs.isRemote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) WorkspacePaneHeader(title: l10n.vault.pageTitle),
        if (homeOffline)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              l10n.vault.homeOfflineHint,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const Expanded(child: VaultPageBody()),
      ],
    );
  }
}
