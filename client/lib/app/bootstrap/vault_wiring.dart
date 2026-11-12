import 'dart:async';

import '../../cubits/github_account_cubit.dart';
import '../../cubits/vault_cubit.dart';
import '../../pages/vault/vault_status_section.dart'
    show promptVaultUnlockFromRouter;
import '../../repositories/app_provider_repository.dart';
import '../../repositories/managed_provider_repository.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../services/github/github_credentials_store.dart';
import '../../services/provider_usage/managed_provider_secret_store.dart';
import '../../services/storage/device_local_control_plane.dart';
import '../../services/storage/home_storage.dart';
import '../../services/vault/credential_capture.dart';
import '../../services/vault/encrypted_vault_backend.dart';
import '../../services/vault/home_vault_service.dart';
import '../../services/vault/keychain_vault_backend.dart';
import '../../services/vault/legacy_import.dart';
import '../../services/vault/vault_access.dart';
import '../../services/vault/vault_service.dart';
import '../../services/vault/vault_split_migration.dart';
import '../../services/vault/vault_unlock_gate.dart';
import '../../utils/logging/logger.dart';

/// The device-local vault core: the SSH credential store, the business vault
/// service with its keychain/encrypted backends, the functional-read accessor,
/// the shared credential-capture path, and the unlock gate.
typedef VaultCoreWiring = ({
  SshCredentialStore sshCredentialStore,
  VaultService service,
  VaultAccess access,
  VaultCredentialCapture credentialCapture,
  VaultUnlockGate unlockGate,
});

/// Builds the vault core.
///
/// [homeVaultScope] is a lazy getter, not a value: the shell assigns the scope
/// once `homeStorage` exists, and the resolver must keep routing to the
/// current home plane across swaps.
Future<VaultCoreWiring> wireVaultCore({
  required String nativeAppDataPath,
  required HomeVaultScope? Function() homeVaultScope,
}) async {
  final sshCredentialStore = const SecureSshCredentialStore(
    FlutterSecureKeyValueStore(),
  );
  final vaultService = VaultService(
    keychainBackend: KeychainVaultBackend(const FlutterSecureKeyValueStore()),
    encryptedBackend: EncryptedVaultBackend(
      repository: deviceLocalVaultRepository(nativeAppDataPath),
    ),
    masterKeyStore: const FlutterSecureKeyValueStore(),
    // Resolved lazily: before assignment, boot-time reads skip the home plane.
    homeVault: () => homeVaultScope()?.service,
  );
  final vaultAccess = VaultAccess(vaultService);
  try {
    await vaultService.initialize();
    // Functional reads (SSH, providers, usage, GitHub) unlock silently with
    // the remembered master password; only an explicit reveal prompts.
    await vaultAccess.tryAutoUnlock();
  } on Object catch (error, stackTrace) {
    appLogger.w(
      '[vault] initialize failed: $error',
      error: error,
      stackTrace: stackTrace,
    );
  }
  // Shared vault-first capture path + unlock gate: every credential writer
  // (GitHub, app providers, SSH setup) goes through these so a locked vault
  // prompts exactly once per action instead of per call site.
  final vaultCredentialCapture = VaultCredentialCapture(vault: vaultService);
  final vaultUnlockGate = VaultUnlockGate(
    vault: vaultService,
    prompt: promptVaultUnlockFromRouter,
  );

  return (
    sshCredentialStore: sshCredentialStore,
    service: vaultService,
    access: vaultAccess,
    credentialCapture: vaultCredentialCapture,
    unlockGate: vaultUnlockGate,
  );
}

/// Builds the home-plane vault cubit.
///
/// Runs before the managed-provider graph, which registers its reference
/// indexer on the cubit. The unlock closure reaches the legacy importer through
/// [legacyImporter]: a getter, because the importer is only constructible after
/// that graph (its repository and secret store come from there).
VaultCubit wireVaultCubit({
  required HomeStorage homeStorage,
  required SshProfileRepository sshProfileRepo,
  required GithubAccountCubit githubAccountCubit,
  required VaultService vaultService,
  required VaultLegacyImportService Function() legacyImporter,
}) {
  late final VaultCubit vaultCubit;
  vaultCubit = VaultCubit(
    service: vaultService,
    sshProfiles: sshProfileRepo,
    appProviders: AppProviderRepository(storage: homeStorage),
    onUnlocked: () async {
      // Import first: GitHub hydration reads the store, and a token that only
      // lives in the vault must be captured before the pointer is consulted.
      // Hydration is NOT awaited: it may hit api.github.com, and unlock/save
      // must stay responsive while it runs.
      await legacyImporter().runOnce();
      // The vault page may already be mounted (the user just unlocked it):
      // re-read rows only; changing status during the unlock transition can
      // re-enter the page rebuild while a dialog is closing.
      await vaultCubit.reloadEntries();
      unawaited(
        githubAccountCubit.hydrate().catchError((
          Object error,
          StackTrace stack,
        ) {
          appLogger.w(
            '[vault] post-unlock GitHub hydrate failed: ${error.runtimeType}',
            stackTrace: stack,
          );
        }),
      );
    },
  );
  return vaultCubit;
}

/// The home-plane vault state that follows the managed-provider graph: the
/// legacy-secret importer plus the subscription that re-syncs the business
/// vault when the home plane swaps.
typedef VaultStateWiring = ({
  VaultLegacyImportService importer,
  StreamSubscription<StoragePlaneChange> planeSyncSubscription,
});

/// Builds the legacy-secret importer, its background hydrate/import sequence,
/// and the home-plane vault sync listener.
///
/// Runs once the managed-provider graph and the GitHub store exist, because
/// the importer imports into both. [homeVaultScope] is the shell-owned lazy
/// getter; the sync listener reads it per change.
VaultStateWiring wireVaultState({
  required HomeStorage homeStorage,
  required SshProfileRepository sshProfileRepo,
  required GithubAccountCubit githubAccountCubit,
  required GithubCredentialsStore githubCredentialsStore,
  required VaultService vaultService,
  required SshCredentialStore sshCredentialStore,
  required VaultCredentialCapture vaultCredentialCapture,
  required String nativeAppDataPath,
  required ManagedProviderRepository resolvedManagedProviderRepository,
  required ManagedProviderSecretStore resolvedManagedProviderSecretStore,
  required VaultCubit vaultCubit,
  required HomeVaultScope? Function() homeVaultScope,
}) {
  // Vault-first migration of every legacy secret. Constructed after the
  // managed-provider graph and the GitHub store so the closure above always
  // sees a fully-assigned importer. `runOnce` is a no-op while the vault is
  // locked and after a clean pass, so it is safe at every boot.
  final legacyImporter = VaultLegacyImportService(
    vault: vaultService,
    capture: vaultCredentialCapture,
    importKey: nativeAppDataPath,
    sshProfiles: sshProfileRepo,
    sshCredentials: sshCredentialStore,
    appProviders: AppProviderRepository(storage: homeStorage),
    managedProviders: resolvedManagedProviderRepository,
    managedSecrets: resolvedManagedProviderSecretStore,
    github: githubCredentialsStore,
  );
  // One background sequence, not two: hydration reads the GitHub store that
  // the import writes, so running them independently can duplicate the vault
  // entry. Failure-tolerant and off the boot critical path.
  unawaited(() async {
    try {
      await githubAccountCubit.hydrate();
      await legacyImporter.runOnce();
      // Repair pass: imports only rows that still carry a plaintext secret and
      // no vault reference, so a provider key added after the one-shot marker
      // (or captured while the plane was down) still reaches the vault.
      await legacyImporter.runRepair();
      // Boot import runs in the background; refresh rows on a possibly-open page.
      await vaultCubit.reloadEntries();
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[vault] boot hydrate/import failed: ${error.runtimeType}',
        stackTrace: stackTrace,
      );
    }
  }());

  // A home switch changes which plane holds the business vault. Both passes are
  // idempotent: copy this device's business entries onto the new plane, then
  // re-run the owner imports so credentials captured while the plane was down
  // (or written before the split) reach it. SSH login credentials stay on the
  // device — the migration skips them.
  final vaultPlaneSyncSub = homeStorage.changes.listen((change) {
    if (!change.newContext.filesystem.isRemote) return;
    final scope = homeVaultScope();
    if (scope == null) return;
    unawaited(() async {
      try {
        await scope.prepare();
        await migrateBusinessVaultEntries(
          device: vaultService,
          home: scope.service,
        );
        await legacyImporter.runRepair();
        await vaultCubit.reloadEntries();
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[vault] home-plane vault sync failed: $error',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }());
  });

  return (importer: legacyImporter, planeSyncSubscription: vaultPlaneSyncSub);
}
