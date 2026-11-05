import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../l10n/app_localizations.dart';
import '../../services/vault/vault_service.dart';
import 'vault_status_section.dart';

/// Re-authenticates before an explicit reveal.
///
/// Keychain-backed vaults return true immediately. Encrypted vaults always ask
/// for the master password again, even when functional reads are unlocked.
/// A locked vault is unlocked only for the duration of the caller's read and
/// never re-arms the remembered password.
Future<bool> authorizeVaultReveal(BuildContext context) async {
  final vault = context.read<VaultService>();
  if (!vault.isEncrypted) return true;
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final passphrase = await showVaultPassphrasePrompt(context);
  if (passphrase == null) return false;
  if (!vault.isUnlocked) {
    try {
      await vault.unlock(passphrase, remember: false);
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
/// Returns null when the entry id/field is empty, the entry is not revealable
/// (for example an SSH private key), or re-authentication fails.
Future<String?> revealVaultSecret(
  BuildContext context,
  String? entryId,
  String field,
) async {
  final id = entryId?.trim() ?? '';
  if (id.isEmpty || field.isEmpty) return null;
  final vault = context.read<VaultService>();
  if (!vault.isEncrypted) return _readAllowed(vault, id, field);

  final wasLocked = vault.isLocked;
  if (!await authorizeVaultReveal(context)) {
    if (wasLocked && vault.isUnlocked) await vault.lock();
    return null;
  }
  final value = await _readAllowed(vault, id, field);
  // A locked vault was decrypted only to answer this reveal; do not leave it
  // unlocked (and never re-remember the password).
  if (wasLocked && vault.isUnlocked) await vault.lock();
  return value;
}

Future<String?> _readAllowed(
  VaultService vault,
  String entryId,
  String field,
) async {
  try {
    final entry = await vault.get(entryId);
    if (entry == null || !entry.revealAllowed) return null;
    final value = entry.fields[field];
    return (value == null || value.isEmpty) ? null : value;
  } on Object {
    return null;
  }
}
