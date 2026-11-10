import '../../models/ssh_profile.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../vault/credential_capture.dart';
import '../vault/vault_capture_guard.dart';
import '../vault/vault_service.dart';
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
/// `''` removes it, a value overwrites it. A first-time save (no owner vault
/// entry) fills an empty active field from the legacy keychain so an unlinked
/// row adopts an existing secret. When an owner entry already exists, the
/// editing guard skips that backfill whenever the active auth-type fields
/// signal "keep" (`null`), so a stale keychain copy cannot overwrite or
/// delete the stored secret.
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
    // An owner entry already holds this device's secret. When the active
    // auth-type fields are `null` they signal "keep"; adopting a (possibly
    // empty) legacy keychain value here would overwrite or delete that
    // stored secret. Password auth keeps on `password`; private-key auth on
    // `privateKey`/`passphrase`. First-time saves (no owner) still adopt
    // legacy values, and explicit values / `''` removals still flow through.
    final owned = await capture.findOwner(
      vaultOwnerKindSshProfile,
      profile.id,
    );
    final activeFieldsKeep = profile.authType == SshAuthType.privateKey
        ? effectivePrivateKey == null && effectivePassphrase == null
        : effectivePassword == null;
    final preserveStored = owned != null && activeFieldsKeep;
    if (!preserveStored) {
      if (profile.authType == SshAuthType.password &&
          (effectivePassword == null || effectivePassword.isEmpty)) {
        effectivePassword = await credentialStore.loadPassword(profile.id);
      }
      if (profile.authType == SshAuthType.privateKey) {
        if (effectivePrivateKey == null || effectivePrivateKey.isEmpty) {
          effectivePrivateKey = await credentialStore.loadPrivateKey(
            profile.id,
          );
        }
        if (effectivePassphrase == null || effectivePassphrase.isEmpty) {
          effectivePassphrase = await credentialStore.loadPrivateKeyPassphrase(
            profile.id,
          );
        }
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

/// Maps editor field state to the writer's three-state secret contract:
/// `null` keeps the stored value, `''` removes it, a value overwrites it.
///
/// Editing or linked keeps an emptied active field (`null`); a new, unlinked
/// row emits `''` for first-save adoption from the legacy keychain. The
/// writer's editing guard skips that backfill when an owner entry already
/// exists and the active fields signal "keep". Inactive auth-type fields are
/// always `''` (remove).
SshEditorSecretInputs sshEditorSecretInputs({
  required SshAuthType authType,
  required bool linked,
  required String passwordText,
  required String privateKeyPem,
  required String passphraseText,
  bool isEditing = false,
}) {
  if (authType == SshAuthType.password) {
    return (
      password: passwordText.isEmpty
          ? ((isEditing || linked) ? null : '')
          : passwordText,
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
  required SshVaultFieldReader? readVaultField,
  required SshCredentialStore credentialStore,
}) async {
  if (authType == SshAuthType.password) {
    var password = _nonEmpty(passwordText);
    password ??= await readVaultField?.call('password');
    password ??= _nonEmpty(await credentialStore.loadPassword(profileId));
    return (password: password, privateKey: null, passphrase: null);
  }
  var privateKey = _nonEmpty(privateKeyPem);
  privateKey ??= await readVaultField?.call('privateKey');
  privateKey ??= _nonEmpty(await credentialStore.loadPrivateKey(profileId));
  var passphrase = _nonEmpty(passphraseText);
  passphrase ??= await readVaultField?.call('passphrase');
  passphrase ??= _nonEmpty(
    await credentialStore.loadPrivateKeyPassphrase(profileId),
  );
  return (password: null, privateKey: privateKey, passphrase: passphrase);
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;

/// Reads a stored credential field for an SSH profile.
///
/// Home-plane rows carry no `vaultEntryId`; fall back to the owner pair the
/// vault itself keeps. This is a functional read — explicit reveals go through
/// `revealVault*` instead, which re-authenticates before showing a secret.
SshVaultFieldReader resolveSshVaultFieldReader(
  VaultService vault,
  SshProfile profile,
) {
  return (field) async {
    final linked = profile.vaultEntryId?.trim() ?? '';
    final entry = linked.isNotEmpty
        ? await vault.get(linked)
        : await findVaultOwnerEntry(
            vault,
            ownerKind: vaultOwnerKindSshProfile,
            ownerId: profile.id,
          );
    final value = entry?.fields[field];
    return (value == null || value.isEmpty) ? null : value;
  };
}
