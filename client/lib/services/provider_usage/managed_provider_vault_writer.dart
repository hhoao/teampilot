import '../../models/managed_provider.dart';
import '../vault/credential_capture.dart';
import '../vault/vault_unlock_gate.dart';

/// Captures managed-provider credentials, then persists the provider row.
///
/// Rollback removes/restores the entry when [persist] fails, so a failed save
/// never leaves the vault ahead of the catalog.
Future<ManagedProvider> saveManagedProviderWithVault({
  required ManagedProvider provider,
  required ManagedProvider? current,
  required Map<String, String> secretValues,
  required VaultCredentialCapture capture,
  required VaultUnlockGate unlockGate,
  required Future<void> Function(ManagedProvider) persist,
}) async {
  if (secretValues.isEmpty) {
    await persist(provider);
    return provider;
  }
  if (!await unlockGate.ensureUnlocked()) {
    throw const VaultSaveBlockedException();
  }
  final existing = current == null
      ? const <String, String>{}
      : await capture.existingManagedFields(current);
  final result = await capture.captureManaged(provider, {
    ...existing,
    ...secretValues,
  });
  final saved = provider.copyWith(vaultEntryId: result.entryId);
  try {
    await persist(saved);
  } on Object {
    await capture.rollback(result);
    rethrow;
  }
  return saved;
}
