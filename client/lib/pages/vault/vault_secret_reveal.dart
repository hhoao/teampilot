import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/vault/vault_service.dart';
import '../../services/vault/vault_unlock_gate.dart';

/// Reads a stored vault field for an on-demand reveal.
///
/// Prompts for the vault passphrase when the encrypted vault is locked.
/// Returns null when the entry id/field is empty or the prompt is cancelled.
Future<String?> revealVaultSecret(
  BuildContext context,
  String? entryId,
  String field,
) async {
  final id = entryId?.trim() ?? '';
  if (id.isEmpty || field.isEmpty) return null;
  final vault = context.read<VaultService>();
  final unlocked = await context.read<VaultUnlockGate>().ensureUnlocked();
  if (!unlocked) return null;
  try {
    return await vault.readField(id, field);
  } on Object {
    return null;
  }
}
