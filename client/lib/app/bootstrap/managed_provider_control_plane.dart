import '../../cubits/managed_provider_cubit.dart';
import '../../cubits/managed_provider_usage_cubit.dart';
import '../../repositories/managed_provider_repository.dart';
import '../../repositories/managed_provider_usage_repository.dart';
import '../../services/io/filesystem.dart';
import '../../services/provider_usage/adapters/codebuddy_credits_adapter.dart';
import '../../services/provider_usage/adapters/grok_dashboard_usage_adapter.dart';
import '../../services/provider_usage/adapters/http_json_mapping_adapter.dart';
import '../../services/provider_usage/adapters/qoder_usage_adapter.dart';
import '../../services/provider_usage/cli_credential_source.dart';
import '../../services/provider_usage/managed_provider_secret_store.dart';
import '../../services/provider_usage/managed_provider_usage_coordinator.dart';
import '../../services/provider_usage/managed_provider_usage_registry.dart';
import '../app_data_bootstrap.dart';

/// This is the control-plane owner for Managed Provider state. It is created
/// once by [buildAppShell] and deliberately contains no workspace identity.
class ManagedProviderControlPlane {
  ManagedProviderControlPlane({
    required this.providerRepository,
    required this.usageRepository,
    required this.secretStore,
    required this.usageRegistry,
    required this.usageCoordinator,
    required this.providerCubit,
    required this.usageCubit,
    this.ownsProviderCubit = false,
    this.ownsUsageCubit = false,
    this.ownsUsageCoordinator = false,
    this.closeOwnedHttpClient,
  });

  final ManagedProviderRepository providerRepository;
  final ManagedProviderUsageRepository usageRepository;
  final ManagedProviderSecretStore secretStore;
  final ManagedProviderUsageRegistry usageRegistry;
  final ManagedProviderUsageCoordinator usageCoordinator;
  final ManagedProviderCubit providerCubit;
  final ManagedProviderUsageCubit usageCubit;
  final bool ownsProviderCubit;
  final bool ownsUsageCubit;
  final bool ownsUsageCoordinator;
  final Future<void> Function()? closeOwnedHttpClient;
  Future<void>? _hydration;
  bool _closed = false;

  Future<void> hydrate({required BootLog boot}) {
    final existing = _hydration;
    if (existing != null) return existing;
    final future = AppDataBootstrap.hydrateManagedProviderData(
      boot: boot,
      managedProviderCubit: providerCubit,
      managedProviderUsageCubit: usageCubit,
    );
    _hydration = future;
    return future;
  }

  Future<void> reload({required BootLog boot}) =>
      AppDataBootstrap.reloadManagedProviderData(
        boot: boot,
        managedProviderCubit: providerCubit,
        managedProviderUsageCubit: usageCubit,
      );

  Future<void> invalidateForStorageContextChange() =>
      usageCubit.invalidateForStorageContextChange();

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (ownsUsageCoordinator) await usageCoordinator.close();
    if (ownsUsageCubit) await usageCubit.close();
    if (ownsProviderCubit) await providerCubit.close();
    final closeHttpClient = closeOwnedHttpClient;
    if (closeHttpClient != null) await closeHttpClient();
  }
}

/// Holds the control-plane resources while [buildAppShell] finishes wiring
/// the shell. On success ownership is transferred to [AppShell]'s caller;
/// otherwise the lease closes the resources exactly once.
class ManagedProviderControlPlaneLease {
  ManagedProviderControlPlaneLease(this.controlPlane);

  final ManagedProviderControlPlane controlPlane;
  bool _ownershipReleased = false;

  void transferOwnership() {
    _ownershipReleased = true;
  }

  Future<void> closeIfOwned() async {
    if (_ownershipReleased) return;
    _ownershipReleased = true;
    await controlPlane.close();
  }
}

/// Builds the CLI-independent adapter catalog used by the AppShell control
/// plane. Official adapters receive application-owned boundaries only.
///
/// Callers that omit the Claude/Codex boundaries keep the fail-closed
/// `unsupported` stubs. Production `buildAppShell` injects file-backed auth
/// readers and the official usage HTTP clients.
ManagedProviderUsageRegistry buildDefaultManagedProviderUsageRegistry({
  CliCredentialSourceResolver? cliCredentials,
  Filesystem? fs,
  String? basePath,
}) {
  return ManagedProviderUsageRegistry([
    HttpJsonMappingAdapter(cliCredentials: cliCredentials),
    GrokDashboardUsageAdapter(cliCredentials: cliCredentials),
    if (fs != null && basePath != null)
      CodebuddyCreditsUsageAdapter(fs: fs, basePath: basePath),
    QoderUsageAdapter(),
  ]);
}
