import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/vault_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../router/app_router.dart';
import '../../widgets/tp_password_input.dart';

class VaultStatusSection extends StatelessWidget {
  const VaultStatusSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<VaultCubit, VaultState>(
      builder: (context, state) {
        final cubit = context.read<VaultCubit>();
        final locked = state.encrypted && !state.unlocked;
        final label = !state.encrypted
            ? l10n.vault.statusKeychain
            : (locked ? l10n.vault.statusEncrypted : l10n.vault.statusUnlocked);
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
                  child: Text(l10n.vault.unlock),
                )
              else if (state.encrypted) ...[
                OutlinedButton(
                  onPressed: cubit.lock,
                  child: Text(l10n.vault.lock),
                ),
                OutlinedButton(
                  onPressed: () => cubit.disableEncryption(),
                  child: Text(l10n.vault.disableEncryption),
                ),
              ] else
                OutlinedButton(
                  onPressed: () => showVaultEnableEncryptionDialog(context),
                  child: Text(l10n.vault.enableEncryption),
                ),
            ],
          ),
        );
      },
    );
  }
}

Future<bool> showVaultUnlockDialog(BuildContext context) async {
  final l10n = context.l10n;
  final cubit = context.read<VaultCubit>();
  final controller = TextEditingController();
  final passphrase = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.vault.unlockTitle),
      content: TpPasswordInput(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.vault.passphrase),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.vault.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: Text(l10n.vault.unlock),
        ),
      ],
    ),
  );
  controller.dispose();
  if (passphrase == null || passphrase.isEmpty) return false;
  await cubit.unlock(passphrase);
  return cubit.state.unlocked;
}

/// Router-based prompt for non-widget call sites (cubits, stores).
Future<bool> promptVaultUnlockFromRouter() async {
  final context = appRouter.routerDelegate.navigatorKey.currentContext;
  if (context == null) return false;
  return showVaultUnlockDialog(context);
}

/// Collects a master password for an explicit reveal without changing state.
Future<String?> showVaultPassphrasePrompt(BuildContext context) async {
  final l10n = context.l10n;
  final controller = TextEditingController();
  final passphrase = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.vault.unlockTitle),
      content: TpPasswordInput(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.vault.passphrase),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.vault.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: Text(l10n.vault.reveal),
        ),
      ],
    ),
  );
  controller.dispose();
  return (passphrase == null || passphrase.isEmpty) ? null : passphrase;
}

Future<void> showVaultEnableEncryptionDialog(BuildContext context) async {
  final l10n = context.l10n;
  final cubit = context.read<VaultCubit>();
  final first = TextEditingController();
  final second = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.vault.enableEncryption),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TpPasswordInput(
            controller: first,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.vault.passphrase),
          ),
          const SizedBox(height: 12),
          TpPasswordInput(
            controller: second,
            decoration: InputDecoration(
              labelText: l10n.vault.passphraseConfirm,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.vault.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (first.text.isEmpty) return;
            if (first.text != second.text) return;
            Navigator.of(dialogContext).pop(true);
          },
          child: Text(l10n.vault.enableEncryption),
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
