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

/// The catalog save returned without the reference actually reaching disk.
class _ReferenceNotPersistedException implements Exception {
  const _ReferenceNotPersistedException();

  @override
  String toString() => 'reference not persisted';
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

  /// In-flight pass per vault, shared by every importer instance so a retried
  /// `buildAppShell` cannot start a second concurrent migration.
  static final _runningByVault = Expando<Future<void>>();

  /// Runs the migration once; concurrent calls share the same pass.
  ///
  /// Safe to call on every launch: the vault marker makes it a no-op after a
  /// clean pass, and a failed pass retries only the owners that did not
  /// finish (finished owners are skipped by their stored reference).
  ///
  /// Single-flight is keyed on the vault, not the instance: a retried
  /// `buildAppShell` constructs a second importer over the same vault, and two
  /// concurrent passes would race on capture/delete.
  Future<void> runOnce() {
    final existing = _runningByVault[_vault];
    if (existing != null) return existing;
    final next = _run().whenComplete(() => _runningByVault[_vault] = null);
    _runningByVault[_vault] = next;
    return next;
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
      // A resolvable pointer with a token is authoritative. Drop any plaintext
      // copy a previous partial pass left behind so a legacy token can never
      // survive alongside marker = 1.
      await _github.migrateLegacyHubPublishTokenIfNeeded();
      await _github.clearLegacyCopy();
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
        if (await _hasVerifiedSshLink(profile)) {
          // The vault entry already holds this profile's secret; only the
          // legacy cleanup remains. Never delete before verifying.
          await _sshCredentials.deleteAll(profile.id);
          continue;
        }
        // No link, or a link whose entry no longer holds the secret: capture
        // from the keychain first, persist the reference, then delete.
        await _captureSshProfile(profile);
        await _sshCredentials.deleteAll(profile.id);
      } on Object catch (error, stackTrace) {
        failures++;
        _warn('ssh ${profile.id}', error, stackTrace);
      }
    }
    if (failures > 0) throw _OwnerImportFailure('ssh', failures);
  }

  /// True when the profile is linked to an entry that still holds the secret
  /// the profile's auth type needs.
  Future<bool> _hasVerifiedSshLink(SshProfile profile) async {
    final entryId = (profile.vaultEntryId ?? '').trim();
    if (entryId.isEmpty) return false;
    final entry = await _vault.get(entryId);
    if (entry == null) return false;
    if (profile.authType == SshAuthType.password) {
      return (entry.fields['password'] ?? '').isNotEmpty;
    }
    return (entry.fields['privateKey'] ?? '').isNotEmpty ||
        (entry.fields['passphrase'] ?? '').isNotEmpty;
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

    // A legacy ref is shared state: it may only be deleted once every provider
    // that points at it has a verified vault entry, otherwise deleting it would
    // destroy the only copy for the other owners.
    final refOwners = <String, int>{};
    for (final provider in providers) {
      final ref = provider.credentialRef?.trim() ?? '';
      if (ref.isNotEmpty) refOwners[ref] = (refOwners[ref] ?? 0) + 1;
    }

    final updated = <ManagedProvider>[];
    final verifiedRefs = <String, int>{};
    final captured = <({String id, String ref})>[];
    var failures = 0;
    var changed = false;

    void verify(String ref) {
      if (ref.isEmpty) return;
      verifiedRefs[ref] = (verifiedRefs[ref] ?? 0) + 1;
    }

    for (final provider in providers) {
      final ref = provider.credentialRef?.trim() ?? '';
      try {
        final entryId = (provider.vaultEntryId ?? '').trim();
        if (entryId.isNotEmpty) {
          final fields = await _capture.existingManagedFields(provider);
          if (fields.isNotEmpty) {
            updated.add(provider);
            verify(ref);
            continue;
          }
          // Dangling/incomplete link: fall through and re-capture from the ref
          // instead of deleting the legacy scope behind it.
        }
        if (ref.isEmpty) {
          updated.add(provider);
          continue;
        }
        final scope = await _readManagedScope(ref);
        if (scope == null || scope.isEmpty) {
          // Nothing stored under this ref, so there is nothing to migrate and
          // nothing that could leak; leave the provider untouched.
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
        captured.add((id: provider.id, ref: ref));
        changed = true;
      } on Object catch (error, stackTrace) {
        failures++;
        _warn('managed ${provider.id}', error, stackTrace);
        updated.add(provider);
      }
    }

    // Save the catalog before deleting anything: a save failure throws here,
    // so a legacy scope is never removed before its reference is persisted.
    if (changed) {
      await _managedProviders.save(updated);
      // A silent save failure would otherwise let the deletion below destroy
      // the only copy, so confirm the references reached disk first.
      final persisted = {
        for (final provider in await _managedProviders.load())
          provider.id: (provider.vaultEntryId ?? '').trim(),
      };
      for (final capture in captured) {
        if ((persisted[capture.id] ?? '').isNotEmpty) {
          verify(capture.ref);
        } else {
          failures++;
          _warn(
            'managed ${capture.id}',
            const _ReferenceNotPersistedException(),
            StackTrace.current,
          );
        }
      }
    }

    for (final entry in refOwners.entries) {
      if (verifiedRefs[entry.key] != entry.value) continue;
      if (!await _deleteManagedRef(entry.key)) failures++;
    }

    if (failures > 0) {
      throw _OwnerImportFailure('managedProvider', failures);
    }
  }

  /// Reads a managed-provider scope. An unusable reference can never address
  /// stored data, so it reads as "nothing stored" instead of a failure.
  Future<ProviderCredentialScope?> _readManagedScope(String ref) async {
    try {
      return await _managedSecrets.read(ref);
    } on ManagedProviderCredentialError catch (error) {
      if (error.code == ManagedProviderCredentialErrorCode.invalidReference) {
        return null;
      }
      rethrow;
    }
  }

  /// Deletes a legacy scope; returns false only for a real storage failure.
  Future<bool> _deleteManagedRef(String ref) async {
    try {
      await _managedSecrets.delete(ref);
      return true;
    } on ManagedProviderCredentialError catch (error, stackTrace) {
      // An unusable reference never had anything stored, so it cannot leak.
      if (error.code == ManagedProviderCredentialErrorCode.invalidReference) {
        return true;
      }
      _warn('managed ref $ref', error, stackTrace);
      return false;
    } on Object catch (error, stackTrace) {
      _warn('managed ref $ref', error, stackTrace);
      return false;
    }
  }

  void _warn(String owner, Object error, StackTrace stackTrace) {
    appLogger.w(
      '[vault-import] $owner failed: ${error.runtimeType}',
      stackTrace: stackTrace,
    );
  }
}
