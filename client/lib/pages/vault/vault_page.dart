import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/vault_cubit.dart';
import '../../l10n/app_localizations.dart';
import 'vault_entry_detail.dart';
import 'vault_entry_editor.dart';
import 'vault_entry_list.dart';
import 'vault_status_section.dart';

class VaultPageBody extends StatefulWidget {
  const VaultPageBody({super.key});

  @override
  State<VaultPageBody> createState() => _VaultPageBodyState();
}

class _VaultPageBodyState extends State<VaultPageBody> {
  @override
  void initState() {
    super.initState();
    // Reload on every mount: the background importer can add entries while
    // the page is closed, and a previous mount may have cached a stale list.
    unawaited(context.read<VaultCubit>().load());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocBuilder<VaultCubit, VaultState>(
      builder: (context, state) {
        if (state.status == VaultStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const VaultStatusSection(),
            const SizedBox(height: 16),
            if (state.status == VaultStatus.locked)
              Text(l10n.vaultStatusEncrypted)
            else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: l10n.vaultSearchHint,
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: context.read<VaultCubit>().setQuery,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => showVaultEntryEditor(context),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.vaultNewEntry),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              VaultEntryList(
                onOpen: (entry) => showVaultEntryDetail(context, entry.id),
              ),
            ],
            if (state.errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                l10n.vaultUnlockFailed,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        );
      },
    );
  }
}
