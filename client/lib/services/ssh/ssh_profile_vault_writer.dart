import '../../models/ssh_profile.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../vault/credential_capture.dart';
import '../vault/vault_unlock_gate.dart';

class SshProfileVaultWriteResult {
  const SshProfileVaultWriteResult({
    required this.profile,
    required this.capture,
  });

  final SshProfile profile;
  final VaultCaptureResult capture;
}

/// Captures SSH secrets in the vault, then saves the profile metadata.
///
/// On failure the capture is rolled back so no orphan entry remains. The
/// keychain is never written.
Future<SshProfileVaultWriteResult> saveSshProfileWithVault({
  required SshProfile profile,
  required String? password,
  required String? privateKey,
  required String? passphrase,
  required VaultCredentialCapture capture,
  required VaultUnlockGate unlockGate,
  required SshProfileRepository repository,
  required SshCredentialStore credentialStore,
}) async {
  if (!await unlockGate.ensureUnlocked()) {
    throw const VaultSaveBlockedException();
  }
  final relayGrant = await credentialStore.loadRelayGrant(profile.id);
  final result = await capture.captureSsh(
    profile,
    password: password,
    privateKey: privateKey,
    passphrase: passphrase,
    relayGrant: relayGrant,
  );
  final saved = profile.copyWith(vaultEntryId: result.entryId);
  try {
    await repository.save(saved);
  } on Object {
    await capture.rollback(result);
    rethrow;
  }
  return SshProfileVaultWriteResult(profile: saved, capture: result);
}
