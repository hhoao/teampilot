import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/vault_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../models/vault_entry.dart';

String vaultTypeLabel(AppLocalizations l10n, VaultEntryType type) =>
    switch (type) {
      VaultEntryType.sshPassword => l10n.vaultTypeSshPassword,
      VaultEntryType.sshPrivateKey => l10n.vaultTypeSshPrivateKey,
      VaultEntryType.apiKey => l10n.vaultTypeApiKey,
      VaultEntryType.login => l10n.vaultTypeLogin,
      VaultEntryType.token => l10n.vaultTypeToken,
      VaultEntryType.secureNote => l10n.vaultTypeSecureNote,
      VaultEntryType.custom => l10n.vaultTypeCustom,
    };

class VaultEntryList extends StatelessWidget {
  const VaultEntryList({required this.onOpen, super.key});

  final ValueChanged<VaultEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocBuilder<VaultCubit, VaultState>(
      builder: (context, state) {
        if (state.entries.isEmpty) {
          return TpEmptyState(
            icon: Icons.lock_outline,
            title: l10n.vaultEmptyTitle,
            hint: l10n.vaultEmptyHint,
            centered: true,
          );
        }
        return Column(
          children: [
            for (final entry in state.entries)
              ListTile(
                key: Key('vault-entry-${entry.id}'),
                leading: Icon(
                  entry.favorite ? Icons.star : Icons.key_outlined,
                ),
                title: Text(entry.title),
                subtitle: Text(
                  '${vaultTypeLabel(l10n, entry.type)} · '
                  '${entry.fields['username'] ?? entry.fields['provider'] ?? ''}',
                ),
                onTap: () => onOpen(entry),
              ),
          ],
        );
      },
    );
  }
}
