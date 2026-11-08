import '../../models/ssh_profile.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../vault/credential_capture.dart';
import '../vault/vault_capture_guard.dart';
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
  final result = await captureThenPersist(
    capture: capture,
    captureEntry: () => capture.captureSsh(
      profile,
      password: effectivePassword,
      privateKey: effectivePrivateKey,
      passphrase: effectivePassphrase,
      relayGrant: relayGrant,
    ),
    persist: (captured) async {
      await repository.save(profile.copyWith(vaultEntryId: captured.entryId));
      return captured;
    },
  );
  final saved = profile.copyWith(vaultEntryId: result.entryId);
  // Only drop the legacy keychain copy once the persisted row actually points
  // at the vault entry. The home-plane server catalog stores `SshServerProfile`
  // (no credential reference), so deleting there would leave that row with no
  // reachable secret at all.
  if (await _persistedVaultEntryId(repository, profile.id) == result.entryId) {
    try {
      await credentialStore.deleteAll(profile.id);
    } on Object {
      // Best effort: the vault already holds the values.
    }
  }
  return SshProfileVaultWriteResult(profile: saved, capture: result);
}

/// The vault reference the catalog actually kept for [profileId], if any.
Future<String?> _persistedVaultEntryId(
  SshProfileRepository repository,
  String profileId,
) async {
  try {
    final stored = await repository.findById(profileId);
    final entryId = stored?.vaultEntryId?.trim() ?? '';
    return entryId.isEmpty ? null : entryId;
  } on Object {
    return null;
  }
}

typedef SshEditorSecretInputs = ({
  String? password,
  String? privateKey,
  String? passphrase,
});

/// Maps editor field state to the writer's null/''/value contract.
///
/// A linked profile keeps an emptied field (`null`); an unlinked profile
/// passes `''` so the writer can adopt the legacy keychain value. The
/// inactive auth-type fields are always `''` (remove).
SshEditorSecretInputs sshEditorSecretInputs({
  required SshAuthType authType,
  required bool linked,
  required String passwordText,
  required String privateKeyPem,
  required String passphraseText,
}) {
  if (authType == SshAuthType.password) {
    return (
      password: passwordText.isEmpty ? (linked ? null : '') : passwordText,
      privateKey: '',
      passphrase: '',
    );
  }
  return (
    password: '',
    privateKey: privateKeyPem.isEmpty ? null : privateKeyPem,
    passphrase: passphraseText.isEmpty ? null : passphraseText,
  );
}

/// Reads one secret field from a linked vault entry.
typedef SshVaultFieldReader = Future<String?> Function(String field);

/// Credentials a "test connection" click should use from an editor.
///
/// Form input wins: a user who just retyped the password must test that
/// password, not the one already stored. An empty field falls back to the
/// linked vault entry and then to the legacy keychain, which is the only
/// remaining source for rows whose catalog record cannot carry a vault
/// reference.
Future<SshEditorSecretInputs> resolveSshEditorTestSecrets({
  required SshAuthType authType,
  required String profileId,
  required String passwordText,
  required String privateKeyPem,
  required String passphraseText,
  required String? vaultEntryId,
  required SshVaultFieldReader? readVaultField,
  required SshCredentialStore credentialStore,
}) async {
  final readVault = (vaultEntryId ?? '').isNotEmpty ? readVaultField : null;
  if (authType == SshAuthType.password) {
    var password = _nonEmpty(passwordText);
    password ??= await readVault?.call('password');
    password ??= _nonEmpty(await credentialStore.loadPassword(profileId));
    return (password: password, privateKey: null, passphrase: null);
  }
  var privateKey = _nonEmpty(privateKeyPem);
  privateKey ??= await readVault?.call('privateKey');
  privateKey ??= _nonEmpty(await credentialStore.loadPrivateKey(profileId));
  var passphrase = _nonEmpty(passphraseText);
  passphrase ??= await readVault?.call('passphrase');
  passphrase ??= _nonEmpty(
    await credentialStore.loadPrivateKeyPassphrase(profileId),
  );
  return (password: null, privateKey: privateKey, passphrase: passphrase);
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;
