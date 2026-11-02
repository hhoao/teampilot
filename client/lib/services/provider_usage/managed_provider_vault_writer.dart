import '../../models/managed_provider.dart';
import '../vault/credential_capture.dart';
import '../vault/vault_unlock_gate.dart';

/// Captures managed-provider credentials, then persists the provider row.
///
/// Rollback removes/restores the entry when [persist] fails, so a failed save
/// never leaves the vault ahead of the catalog. A rollback failure never masks
/// the persistence error.
Future<ManagedProvider> saveManagedProviderWithVault({
  required ManagedProvider provider,
  required Map<String, String> existingValues,
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
  final result = await capture.captureManaged(provider, {
    ...existingValues,
    ...secretValues,
  });
  final saved = provider.copyWith(vaultEntryId: result.entryId);
  try {
    await persist(saved);
  } on Object {
    try {
      await capture.rollback(result);
    } on Object {
      // Preserve the persistence error.
    }
    rethrow;
  }
  return saved;
}
