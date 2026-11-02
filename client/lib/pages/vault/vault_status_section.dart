import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/vault_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/tp_password_input.dart';

class VaultStatusSection extends StatelessWidget {
  const VaultStatusSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocBuilder<VaultCubit, VaultState>(
      builder: (context, state) {
        final cubit = context.read<VaultCubit>();
        final locked = state.encrypted && !state.unlocked;
        final label = !state.encrypted
            ? l10n.vaultStatusKeychain
            : (locked ? l10n.vaultStatusEncrypted : l10n.vaultStatusUnlocked);
        return TpCard(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(label),
              if (locked)
                FilledButton(
                  onPressed: () => showVaultUnlockDialog(context),
                  child: Text(l10n.vaultUnlock),
                )
              else if (state.encrypted) ...[
                OutlinedButton(
                  onPressed: cubit.lock,
                  child: Text(l10n.vaultLock),
                ),
                OutlinedButton(
                  onPressed: () => cubit.disableEncryption(),
                  child: Text(l10n.vaultDisableEncryption),
                ),
              ] else
                OutlinedButton(
                  onPressed: () => showVaultEnableEncryptionDialog(context),
                  child: Text(l10n.vaultEnableEncryption),
                ),
            ],
          ),
        );
      },
    );
  }
}

Future<void> showVaultUnlockDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final cubit = context.read<VaultCubit>();
  final controller = TextEditingController();
  final passphrase = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.vaultUnlockTitle),
      content: TpPasswordInput(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.vaultPassphrase),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.vaultCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: Text(l10n.vaultUnlock),
        ),
      ],
    ),
  );
  controller.dispose();
  if (passphrase == null || passphrase.isEmpty) return;
  await cubit.unlock(passphrase);
}

Future<void> showVaultEnableEncryptionDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final cubit = context.read<VaultCubit>();
  final first = TextEditingController();
  final second = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.vaultEnableEncryption),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TpPasswordInput(
            controller: first,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.vaultPassphrase),
          ),
          const SizedBox(height: 12),
          TpPasswordInput(
            controller: second,
            decoration: InputDecoration(labelText: l10n.vaultPassphraseConfirm),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.vaultCancel),
        ),
        FilledButton(
          onPressed: () {
            if (first.text.isEmpty) return;
            if (first.text != second.text) return;
            Navigator.of(dialogContext).pop(true);
          },
          child: Text(l10n.vaultEnableEncryption),
        ),
      ],
    ),
  );
  final passphrase = first.text;
  first.dispose();
  second.dispose();
  if (confirmed != true || passphrase.isEmpty) return;
  await cubit.enableEncryption(passphrase);
}
