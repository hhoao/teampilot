import '../../models/app_provider_config.dart';
import '../../models/managed_provider.dart';
import '../../models/ssh_profile.dart';
import '../../models/team_config.dart';
import '../../repositories/app_provider_repository.dart';
import '../../repositories/managed_provider_repository.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../utils/logging/logger.dart';
import '../github/github_credentials_store.dart';
import '../provider_usage/managed_provider_secret_store.dart';
import 'credential_capture.dart';
import 'vault_service.dart';

/// Raised when at least one owner of a category could not be imported.
///
/// Carries counts and ids only — never secret material.
class _OwnerImportFailure implements Exception {
  const _OwnerImportFailure(this.owner, this.failures);

  final String owner;
  final int failures;

  @override
  String toString() => 'legacy import incomplete for $owner ($failures failed)';
}

/// Imports every legacy secret into the vault exactly once.
///
/// Order: GitHub → SSH → app providers → managed providers. Each owner is
/// isolated; a failed owner keeps its legacy value and blocks the completion
/// marker so the next run retries only unfinished owners. The marker is
/// written only when a full pass has zero failures.
///
/// Every step follows capture → verify → persist reference → delete legacy, so
/// a crash at any point leaves the secret readable from at least one place.
class VaultLegacyImportService {
  VaultLegacyImportService({
    required VaultService vault,
    required VaultCredentialCapture capture,
    required SshProfileRepository sshProfiles,
    required SshCredentialStore sshCredentials,
    required AppProviderRepository appProviders,
    required ManagedProviderRepository managedProviders,
    required ManagedProviderSecretStore managedSecrets,
    required GithubCredentialsStore github,
  }) : _vault = vault,
       _capture = capture,
       _sshProfiles = sshProfiles,
       _sshCredentials = sshCredentials,
       _appProviders = appProviders,
       _managedProviders = managedProviders,
       _managedSecrets = managedSecrets,
       _github = github;

  static const _version = 1;

  final VaultService _vault;
  final VaultCredentialCapture _capture;
  final SshProfileRepository _sshProfiles;
  final SshCredentialStore _sshCredentials;
  final AppProviderRepository _appProviders;
  final ManagedProviderRepository _managedProviders;
  final ManagedProviderSecretStore _managedSecrets;
  final GithubCredentialsStore _github;

  Future<void>? _running;

  /// Runs the migration once; concurrent calls share the same pass.
  ///
  /// Safe to call on every launch: the vault marker makes it a no-op after a
  /// clean pass, and a failed pass retries only the owners that did not
  /// finish (finished owners are skipped by their stored reference).
  Future<void> runOnce() {
    final active = _running;
    if (active != null) return active;
    final next = _run();
    _running = next.whenComplete(() => _running = null);
    return _running!;
  }

  Future<void> _run() async {
    if (!_vault.isUnlocked) return;
    if (_vault.legacyImportVersion >= _version) return;

    var failed = false;
    failed = !await _guard('github', _importGithub) || failed;
    failed = !await _guard('ssh', _importSsh) || failed;
    for (final cli in CliTool.values) {
      failed =
          !await _guard(
            'appProvider:${cli.value}',
            () => _importProviders(cli),
          ) ||
          failed;
    }
    failed = !await _guard('managedProvider', _importManaged) || failed;

    if (failed) return;
    try {
      await _vault.markLegacyImported(_version);
    } on Object catch (error, stackTrace) {
      // The import itself succeeded, so a retry is harmless: every step is
      // idempotent and the marker is the only thing left to persist.
      _warn('marker', error, stackTrace);
    }
  }

  /// Runs one owner category, logging its type (never its values) on failure.
  Future<bool> _guard(String owner, Future<void> Function() body) async {
    try {
      await body();
      return true;
    } on Object catch (error, stackTrace) {
      _warn(owner, error, stackTrace);
      return false;
    }
  }

  Future<void> _importGithub() async {
    final pointer = await _github.storedVaultEntryId();
    if (pointer != null && await _vault.readField(pointer, 'token') != null) {
      // A resolvable pointer with a token is authoritative: the legacy keys
      // were cleared when it was written, so there is nothing left to import.
      return;
    }
    // No pointer yet, or one that no longer resolves to a token (a locked or
    // partial delete can leave the legacy token behind): import the snapshot
    // and let the store persist a fresh pointer, clearing the legacy keys.
    final snapshot = await _github.readStored();
    if (snapshot == null || snapshot.token.isEmpty) return;
    if (snapshot.source == GithubCredentialSource.pat) {
      await _github.savePat(snapshot.token, login: snapshot.login);
    } else {
      await _github.saveOAuth(
        token: snapshot.token,
        login: snapshot.login ?? '',
      );
    }
  }

  Future<void> _importSsh() async {
    var failures = 0;
    for (final profile in await _sshProfiles.loadAll()) {
      try {
        if ((profile.vaultEntryId ?? '').trim().isEmpty) {
          await _captureSshProfile(profile);
        }
        // Also reached for an already-linked profile, so a pass that stored
        // the reference but failed to delete the keychain copy converges
        // instead of leaving a duplicate secret behind.
        await _sshCredentials.deleteAll(profile.id);
      } on Object catch (error, stackTrace) {
        failures++;
        _warn('ssh ${profile.id}', error, stackTrace);
      }
    }
    if (failures > 0) throw _OwnerImportFailure('ssh', failures);
  }

  Future<void> _captureSshProfile(SshProfile profile) async {
    final passwordAuth = profile.authType == SshAuthType.password;
    final password = passwordAuth
        ? await _sshCredentials.loadPassword(profile.id)
        : null;
    final privateKey = passwordAuth
        ? null
        : await _sshCredentials.loadPrivateKey(profile.id);
    final passphrase = passwordAuth
        ? null
        : await _sshCredentials.loadPrivateKeyPassphrase(profile.id);
    final relayGrant = await _sshCredentials.loadRelayGrant(profile.id);
    final hasSecret =
        (password ?? '').isNotEmpty ||
        (privateKey ?? '').isNotEmpty ||
        (passphrase ?? '').isNotEmpty ||
        (relayGrant ?? '').isNotEmpty;
    if (!hasSecret) return;

    final result = await _capture.captureSsh(
      profile,
      password: password,
      privateKey: privateKey,
      passphrase: passphrase,
      relayGrant: relayGrant,
    );
    try {
      await _sshProfiles.save(profile.copyWith(vaultEntryId: result.entryId));
    } on Object {
      // The reference did not stick, so the captured entry must not survive.
      await _capture.rollback(result);
      rethrow;
    }
  }

  Future<void> _importProviders(CliTool cli) async {
    // Copy before mutating: with `reconcileCredentials: false` the repository
    // may hand back its own cached list, and a failed save must not leave the
    // cache claiming a reference that never reached disk.
    final providers = [
      ...await _appProviders.loadProviders(cli, reconcileCredentials: false),
    ];
    var failures = 0;
    var changed = false;
    for (var index = 0; index < providers.length; index++) {
      final provider = providers[index];
      try {
        // A link already owns the credential; its persisted key is stripped
        // by [AppProviderRepository.saveProviders].
        if (provider.credentialLink.trim().isNotEmpty) continue;
        if (provider.apiKey.isEmpty) continue;
        final result = await _capture.captureProvider(
          provider,
          apiKey: provider.apiKey,
        );
        providers[index] = provider.copyWith(
          credentialLink: 'vault:${result.entryId}',
          apiKey: '',
        );
        changed = true;
      } on Object catch (error, stackTrace) {
        failures++;
        _warn('provider ${provider.id}', error, stackTrace);
      }
    }
    // Persist the owners that succeeded before reporting the failures; the
    // untouched rows keep their plaintext key for a later retry.
    if (changed) await _appProviders.saveProviders(cli, providers);
    if (failures > 0) {
      throw _OwnerImportFailure('appProvider:${cli.value}', failures);
    }
  }

  Future<void> _importManaged() async {
    final providers = await _managedProviders.load();
    final updated = <ManagedProvider>[];
    final legacyRefs = <String>[];
    var failures = 0;
    var changed = false;
    for (final provider in providers) {
      final ref = provider.credentialRef?.trim() ?? '';
      try {
        if ((provider.vaultEntryId ?? '').trim().isNotEmpty) {
          // Already linked; deleting the legacy scope is a no-op when the
          // earlier pass cleaned it up and converges when it did not.
          updated.add(provider);
          if (ref.isNotEmpty) legacyRefs.add(ref);
          continue;
        }
        if (ref.isEmpty) {
          updated.add(provider);
          continue;
        }
        final scope = await _managedSecrets.read(ref);
        if (scope.isEmpty) {
          updated.add(provider);
          continue;
        }
        final values = {
          for (final field in scope.fields)
            if ((scope.valueFor(field) ?? '').isNotEmpty)
              field: scope.valueFor(field)!,
        };
        final result = await _capture.captureManaged(provider, values);
        updated.add(provider.copyWith(vaultEntryId: result.entryId));
        legacyRefs.add(ref);
        changed = true;
      } on Object catch (error, stackTrace) {
        failures++;
        _warn('managed ${provider.id}', error, stackTrace);
        updated.add(provider);
      }
    }
    // Save the catalog before deleting anything: a save failure throws here,
    // so a legacy scope is never removed before its reference is persisted.
    if (changed) await _managedProviders.save(updated);
    for (final ref in legacyRefs) {
      try {
        await _managedSecrets.delete(ref);
      } on ManagedProviderCredentialError catch (error, stackTrace) {
        // An unusable reference never had anything stored, so it cannot leak.
        if (error.code == ManagedProviderCredentialErrorCode.invalidReference) {
          continue;
        }
        failures++;
        _warn('managed ref $ref', error, stackTrace);
      } on Object catch (error, stackTrace) {
        failures++;
        _warn('managed ref $ref', error, stackTrace);
      }
    }
    if (failures > 0) {
      throw _OwnerImportFailure('managedProvider', failures);
    }
  }

  void _warn(String owner, Object error, StackTrace stackTrace) {
    appLogger.w(
      '[vault-import] $owner failed: ${error.runtimeType}',
      stackTrace: stackTrace,
    );
  }
}
