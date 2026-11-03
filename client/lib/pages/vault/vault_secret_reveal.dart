import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../l10n/app_localizations.dart';
import '../../services/vault/vault_service.dart';
import 'vault_status_section.dart';

/// Re-authenticates before an explicit reveal.
///
/// Keychain-backed vaults return true immediately. Encrypted vaults always ask
/// for the master password again, even when functional reads are unlocked.
Future<bool> authorizeVaultReveal(BuildContext context) async {
  final vault = context.read<VaultService>();
  if (!vault.isEncrypted) return true;
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final passphrase = await showVaultPassphrasePrompt(context);
  if (passphrase == null) return false;
  if (!vault.isUnlocked) {
    try {
      await vault.unlock(passphrase);
      return true;
    } on Object {
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.vaultUnlockFailed)),
      );
      return false;
    }
  }
  if (await vault.verifyMasterPassphrase(passphrase)) return true;
  messenger?.showSnackBar(
    SnackBar(content: Text(l10n.vaultUnlockFailed)),
  );
  return false;
}

/// Reads a stored vault field for an explicit reveal.
///
/// Returns null when the entry id/field is empty or re-authentication fails.
Future<String?> revealVaultSecret(
  BuildContext context,
  String? entryId,
  String field,
) async {
  final id = entryId?.trim() ?? '';
  if (id.isEmpty || field.isEmpty) return null;
  final vault = context.read<VaultService>();
  if (vault.isEncrypted && !await authorizeVaultReveal(context)) {
    return null;
  }
  try {
    return await vault.readField(id, field);
  } on Object {
    return null;
  }
}
