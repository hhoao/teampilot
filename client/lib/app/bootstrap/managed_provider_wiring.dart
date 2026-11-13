import 'dart:async';

import 'package:collection/collection.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../cubits/managed_provider_cubit.dart';
import '../../cubits/managed_provider_usage_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../cubits/vault_cubit.dart';
import '../../models/team_config.dart';
import '../../models/vault_reference.dart';
import '../../repositories/app_provider_repository.dart';
import '../../repositories/managed_provider_repository.dart';
import '../../repositories/managed_provider_usage_repository.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../services/github/github_credentials_store.dart';
import '../../services/provider_usage/adapters/claude_official_subscription_auth.dart';
import '../../services/provider_usage/adapters/codex_official_subscription_auth.dart';
import '../../services/provider_usage/adapters/cursor_official_subscription_auth.dart';
import '../../services/provider_usage/cli_credential_source.dart';
import '../../services/provider_usage/managed_provider_cli_row_janitor.dart';
import '../../services/provider_usage/managed_provider_link_janitor.dart';
import '../../services/provider_usage/managed_provider_secret_store.dart';
import '../../services/provider_usage/managed_provider_usage_adapter.dart';
import '../../services/provider_usage/managed_provider_usage_coordinator.dart';
import '../../services/provider_usage/managed_provider_usage_registry.dart';
import '../../services/ssh/ssh_connection_gate.dart';
import '../../services/storage/home_storage.dart';
import '../../services/vault/credential_capture.dart';
import '../../services/vault/provider_credential_link.dart';
import '../../services/vault/vault_access.dart';
import '../../services/vault/vault_reference_indexer.dart';
import '../../services/vault/vault_service.dart';
import '../../services/vault/vault_unlock_gate.dart';
import '../../utils/logging/logger.dart';
import '../app_data_bootstrap.dart';
import 'managed_provider_control_plane.dart';
import 'provider_usage_http_client.dart';

/// The managed-provider graph owned by the home/control plane.
///
/// [hydrate] is a deferred cache warm-up: the shell arms it through a factory
/// and invokes it later, never during wiring. `openCredentialLoginUrl` is the
/// single external-browser opener shared with the per-CLI credential host
/// runner the shell builds afterwards.
typedef ManagedProviderWiring = ({
  AppProviderCubit appProviderCubit,
  ManagedProviderCubit providerCubit,
  ManagedProviderUsageCubit usageCubit,
  ManagedProviderControlPlane controlPlane,
  ManagedProviderControlPlaneLease controlPlaneLease,
  Future<void> Function(Uri uri) openCredentialLoginUrl,
  Future<void> Function() hydrate,
});

/// Builds the managed-provider graph once, after the home context exists.
///
/// Workspace tabs only consume the cubits exposed by `AppShell`; they never
/// create provider-specific state. The startup CLI-row sweep is scheduled here
/// (fire-and-forget) because it needs the row janitor and the repository that
/// never leave this graph.
ManagedProviderWiring wireManagedProviders({
  required HomeStorage storage,
  required VaultCubit Function() vaultCubit,
  required VaultAccess vaultAccess,
  required VaultService vaultService,
  required VaultCredentialCapture vaultCredentialCapture,
  required VaultUnlockGate vaultUnlockGate,
  required SshProfileRepository sshProfiles,
  required GithubCredentialsStore githubCredentials,
  required SessionPreferencesCubit sessionPreferences,
  required BootLog boot,
  required ManagedProviderRepository? repositoryOverride,
  required ManagedProviderUsageRepository? usageRepositoryOverride,
  required ManagedProviderSecretStore? secretStoreOverride,
  required ManagedProviderUsageRegistry? usageRegistryOverride,
  required ManagedProviderUsageCoordinator? usageCoordinatorOverride,
  required ManagedProviderCubit? cubitOverride,
  required ManagedProviderUsageCubit? usageCubitOverride,
  required ProviderUsageHttpClient? httpClientOverride,
  required CliCredentialSourceResolver? cliCredentialsOverride,
}) {
  final resolvedManagedProviderSecretStore =
      secretStoreOverride ??
      ManagedProviderSecretStore(const FlutterSecureKeyValueStore());
  final resolvedManagedProviderUsageRepository =
      usageRepositoryOverride ??
      ManagedProviderUsageRepository(storage: storage);
  final resolvedManagedProviderRepository =
      repositoryOverride ??
      ManagedProviderRepository(
        storage: storage,
        onProvidersDeleted: resolvedManagedProviderUsageRepository.deleteMany,
      );

  vaultCubit().attachReferenceIndexer(
    VaultReferenceIndexer([
      (entryId) async {
        final profiles = await sshProfiles.loadAll();
        return [
          for (final profile in profiles)
            if (profile.vaultEntryId == entryId)
              VaultReference(
                kind: VaultReferenceKind.sshProfile,
                id: profile.id,
                label: profile.name,
              ),
        ];
      },
      (entryId) async {
        final perCli = await Future.wait([
          for (final cli in CliTool.values)
            AppProviderRepository(
              storage: storage,
            ).loadProviders(cli, reconcileCredentials: false),
        ]);
        return [
          for (final providers in perCli)
            for (final provider in providers)
              if (vaultEntryIdFromCredentialLink(provider.credentialLink) ==
                  entryId)
                VaultReference(
                  kind: VaultReferenceKind.appProvider,
                  id: provider.id,
                  label: provider.name,
                ),
        ];
      },
      (entryId) async {
        final entries = await resolvedManagedProviderRepository.load();
        return [
          for (final entry in entries)
            if ((entry.vaultEntryId ?? '').trim() == entryId)
              VaultReference(
                kind: VaultReferenceKind.managedProvider,
                id: entry.id,
                label: entry.name,
              ),
        ];
      },
      (entryId) async {
        final stored = await githubCredentials.storedVaultEntryId();
        if ((stored ?? '').trim() != entryId) return const [];
        return const [
          VaultReference(
            kind: VaultReferenceKind.github,
            id: 'github',
            label: 'GitHub',
          ),
        ];
      },
    ]),
  );
  final ownsManagedProviderHttpClient =
      httpClientOverride == null && usageCoordinatorOverride == null;
  final ProviderUsageHttpClient? resolvedManagedProviderHttpClient =
      httpClientOverride ??
      (usageCoordinatorOverride == null
          ? DefaultProviderUsageHttpClient()
          : null);
  final resolvedManagedProviderUsageRegistry =
      usageRegistryOverride ??
      buildDefaultManagedProviderUsageRegistry(
        fs: storage.fs,
        basePath: storage.paths.basePath,
        cliCredentials:
            cliCredentialsOverride ??
            CliCredentialSourceResolver(
              readers: {
                'claude': ClaudeOfficialSubscriptionAuthReader(
                  fs: storage.fs,
                  basePath: storage.paths.basePath,
                ),
                'codex': CodexOfficialSubscriptionAuthReader(
                  fs: storage.fs,
                  basePath: storage.paths.basePath,
                ),
                'cursor': CursorOfficialSubscriptionAuthReader(
                  fs: storage.fs,
                  basePath: storage.paths.basePath,
                ),
              },
            ),
      );
  final resolvedManagedProviderUsageCoordinator =
      usageCoordinatorOverride ??
      ManagedProviderUsageCoordinator(
        providerRepository: resolvedManagedProviderRepository,
        usageRepository: resolvedManagedProviderUsageRepository,
        registry: resolvedManagedProviderUsageRegistry,
        credentials: ManagedProviderCredentialResolver(
          resolvedManagedProviderSecretStore,
          // Live `provider:<cli>:<id>` credential sources read the app
          // provider catalog; a dedicated repository instance avoids the
          // (later-constructed) cubit's load-order dependency. Same disk,
          // same cache-free reads.
          appProviders: AppProviderRepository(storage: storage),
          vault: vaultAccess,
        ),
        http: resolvedManagedProviderHttpClient!,
      );
  final resolvedManagedProviderUsageCubit =
      usageCubitOverride ??
      ManagedProviderUsageCubit(
        coordinator: resolvedManagedProviderUsageCoordinator,
      );
  // Credential-login URL opener shared by the app provider cubit and the
  // per-CLI credential host runner; declared before the managed-provider
  // control plane so AppProviderCubit can be constructed above it.
  Future<void> openCredentialLoginUrl(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // Resolves a provider config's `credentialLink` to the linked managed
  // entry's stored secret (spec: reverse direction). Secret-free failure: a
  // missing entry or secret resolves to null, never throws.
  Future<String?> appProviderLinkedCredentialLookup(String link) async {
    final vaultEntryId = vaultEntryIdFromCredentialLink(link);
    if (vaultEntryId != null) {
      try {
        return await vaultAccess.functionalField(vaultEntryId, 'apiKey');
      } on Object {
        return null;
      }
    }
    final entries = await resolvedManagedProviderRepository.load();
    final entry = entries.where((e) => e.id == link.trim()).firstOrNull;
    if (entry == null) return null;
    final entryVaultEntryId = entry.vaultEntryId?.trim() ?? '';
    if (entryVaultEntryId.isNotEmpty) {
      final field = entry.endpointConfig.credentialField ?? 'apiKey';
      try {
        return await vaultAccess.functionalField(entryVaultEntryId, field);
      } on Object {
        return null;
      }
    }
    final ref = entry.credentialRef?.trim();
    if (ref == null || ref.isEmpty) return null;
    final scope = await resolvedManagedProviderSecretStore.read(ref);
    final field = entry.endpointConfig.credentialField ?? 'apiKey';
    final value = scope.valueFor(field);
    return (value == null || value.isEmpty) ? null : value;
  }

  // CLI launch resolvers create their own AppProviderRepository instances
  // (OpenCode, Claude, cross-machine bridges); give them the vault-aware
  // lookup so `vault:` links resolve outside the provider cubit too.
  AppProviderRepository.installDefaultLinkedCredentialLookup(
    appProviderLinkedCredentialLookup,
  );

  // Constructed before the managed-provider control plane so
  // ManagedProviderCubit can ensure dedicated per-entry CLI provider rows;
  // only needs sessionPreferences and openCredentialLoginUrl.
  final appProviderCubit = AppProviderCubit(
    storage: storage,
    repository: AppProviderRepository(
      storage: storage,
      linkedCredentialLookup: appProviderLinkedCredentialLookup,
    ),
    flashskyaiExecutablePath: sessionPreferences.resolveExecutable,
    openCredentialLoginUrl: openCredentialLoginUrl,
    managedProviderRepository: resolvedManagedProviderRepository,
    vaultCapture: vaultCredentialCapture,
    ensureVaultUnlocked: vaultUnlockGate.ensureUnlocked,
  );

  // Reclaims dedicated CLI provider rows and their isolated HOME
  // directories: from the managed-provider delete hook and the one-shot
  // startup sweep below.
  final managedProviderCliRowJanitor = ManagedProviderCliRowJanitor(
    fs: storage.fs,
    basePath: storage.paths.basePath,
    appProviderCubit: appProviderCubit,
  );

  final resolvedManagedProviderCubit =
      cubitOverride ??
      ManagedProviderCubit(
        repository: resolvedManagedProviderRepository,
        appProviderCubit: appProviderCubit,
        rowJanitor: managedProviderCliRowJanitor,
        ensureVaultUnlocked: vaultUnlockGate.ensureUnlocked,
        onProviderDeletedState:
            resolvedManagedProviderUsageCubit.removeProvider,
        onProviderDeletedCredentialCleanup: (provider) async {
          final vaultEntryId = provider.vaultEntryId?.trim() ?? '';
          if (vaultEntryId.isNotEmpty) {
            try {
              await vaultService.delete(vaultEntryId);
            } on Object catch (error, stackTrace) {
              appLogger.w(
                'Vault entry cleanup failed for managed provider ${provider.id}',
                error: error,
                stackTrace: stackTrace,
              );
            }
          }
          final ref = provider.credentialRef?.trim();
          if (ref != null && ref.isNotEmpty) {
            await resolvedManagedProviderSecretStore.delete(ref);
          }
          // Clear provider-config rows that referenced this entry's secret.
          await ManagedProviderLinkJanitor(
            appProviderCubit: appProviderCubit,
          ).clearLinksFor(provider.id);
        },
      );
  final managedProviderControlPlane = ManagedProviderControlPlane(
    providerRepository: resolvedManagedProviderRepository,
    usageRepository: resolvedManagedProviderUsageRepository,
    secretStore: resolvedManagedProviderSecretStore,
    usageRegistry: resolvedManagedProviderUsageRegistry,
    usageCoordinator: resolvedManagedProviderUsageCoordinator,
    providerCubit: resolvedManagedProviderCubit,
    usageCubit: resolvedManagedProviderUsageCubit,
    ownsProviderCubit: cubitOverride == null,
    ownsUsageCubit: usageCubitOverride == null,
    ownsUsageCoordinator: usageCoordinatorOverride == null,
    closeOwnedHttpClient: ownsManagedProviderHttpClient
        ? () =>
              (resolvedManagedProviderHttpClient!
                      as DefaultProviderUsageHttpClient)
                  .close()
        : null,
  );
  final managedProviderControlPlaneLease = ManagedProviderControlPlaneLease(
    managedProviderControlPlane,
  );

  // One-shot startup sweep: reclaim orphaned `-mp-` rows and the legacy
  // shared rows. Fire-and-forget and failure-tolerant — the control plane
  // is fully usable without it.
  unawaited(() async {
    try {
      final entries = await resolvedManagedProviderRepository.load();
      await managedProviderCliRowJanitor.sweep(entries: entries);
    } on Object catch (error, stackTrace) {
      if (isSshProfileDown(error)) {
        appLogger.d(
          '[managed-provider] cli row sweep waiting for home transport',
          error: error,
          stackTrace: stackTrace,
        );
        return;
      }
      appLogger.w(
        '[managed-provider] cli row sweep failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }());

  // Deferred warm-up: the shell calls this once the first frame is painted.
  // Never invoked here. The control plane also memoizes the future, but the
  // shell keeps a single handle so repeated bootstrap passes share it.
  Future<void>? managedProviderHydration;
  Future<void> hydrate() {
    final existing = managedProviderHydration;
    if (existing != null) return existing;
    final future = managedProviderControlPlane.hydrate(boot: boot);
    managedProviderHydration = future;
    return future;
  }

  return (
    appProviderCubit: appProviderCubit,
    providerCubit: resolvedManagedProviderCubit,
    usageCubit: resolvedManagedProviderUsageCubit,
    controlPlane: managedProviderControlPlane,
    controlPlaneLease: managedProviderControlPlaneLease,
    openCredentialLoginUrl: openCredentialLoginUrl,
    hydrate: hydrate,
  );
}
