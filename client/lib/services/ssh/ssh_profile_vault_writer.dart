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
/// Field semantics match the capture service: `null` keeps the stored value,
/// `''` removes it, a value overwrites it. For a profile that is not linked
/// yet, empty password/key/passphrase arguments are filled from the legacy
/// keychain so an edit never silently drops an existing secret.
///
/// The keychain is never written. After the profile is saved, its legacy
/// keychain secrets are deleted (best effort); a failure there does not fail
/// the save because the vault already holds the values.
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
  final linked = (profile.vaultEntryId ?? '').isNotEmpty;
  var effectivePassword = password;
  var effectivePrivateKey = privateKey;
  var effectivePassphrase = passphrase;
  if (!linked) {
    if (profile.authType == SshAuthType.password &&
        (effectivePassword == null || effectivePassword.isEmpty)) {
      effectivePassword = await credentialStore.loadPassword(profile.id);
    }
    if (profile.authType == SshAuthType.privateKey) {
      if (effectivePrivateKey == null || effectivePrivateKey.isEmpty) {
        effectivePrivateKey = await credentialStore.loadPrivateKey(profile.id);
      }
      if (effectivePassphrase == null || effectivePassphrase.isEmpty) {
        effectivePassphrase = await credentialStore.loadPrivateKeyPassphrase(
          profile.id,
        );
      }
    }
  }
  final relayGrant = await credentialStore.loadRelayGrant(profile.id);
  final result = await capture.captureSsh(
    profile,
    password: effectivePassword,
    privateKey: effectivePrivateKey,
    passphrase: effectivePassphrase,
    relayGrant: relayGrant,
  );
  final saved = profile.copyWith(vaultEntryId: result.entryId);
  try {
    await repository.save(saved);
  } on Object {
    try {
      await capture.rollback(result);
    } on Object {
      // Preserve the repository error; the final review can spot orphans.
    }
    rethrow;
  }
  try {
    await credentialStore.deleteAll(profile.id);
  } on Object {
    // Best effort: the vault already holds the values.
  }
  return SshProfileVaultWriteResult(profile: saved, capture: result);
}
