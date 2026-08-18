import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/app/app_shell.dart';
import 'package:teampilot/cubits/managed_provider_cubit.dart';
import 'package:teampilot/cubits/managed_provider_usage_cubit.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_usage_repository.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_coordinator.dart'
    as coordinator;
import 'package:teampilot/services/provider_usage/managed_provider_usage_registry.dart';
import 'package:teampilot/services/provider_usage/managed_provider_secret_store.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';

void main() {
  test(
    'control-plane hydration is single-flight and reload reuses cubits',
    () async {
      final repository = _FakeManagedProviderRepository();
      final coordinator = _FakeManagedProviderUsageCoordinator();
      final providerCubit = ManagedProviderCubit(repository: repository);
      final usageCubit = ManagedProviderUsageCubit(coordinator: coordinator);
      final controlPlane = ManagedProviderControlPlane(
        providerRepository: repository,
        usageRepository: ManagedProviderUsageRepository(),
        secretStore: ManagedProviderSecretStore(_EmptySecureStore()),
        usageRegistry: ManagedProviderUsageRegistry(),
        usageCoordinator: coordinator,
        providerCubit: providerCubit,
        usageCubit: usageCubit,
      );
      addTearDown(providerCubit.close);
      addTearDown(usageCubit.close);

      expect(controlPlane.providerCubit, same(providerCubit));
      expect(controlPlane.usageCubit, same(usageCubit));

      final hydration = controlPlane.hydrate(boot: (_) {});
      await Future.wait([hydration, hydration]);

      expect(repository.loadCalls, 1);
      expect(coordinator.loadCalls, 1);
      expect(usageCubit, same(usageCubit));
      expect(providerCubit.state.providers, hasLength(1));

      await controlPlane.reload(boot: (_) {});

      expect(repository.loadCalls, 2);
      expect(coordinator.loadCalls, 2);
      expect(providerCubit.state.providers, hasLength(1));
    },
  );
}

class _FakeManagedProviderRepository extends ManagedProviderRepository {
  _FakeManagedProviderRepository() : super(onProvidersDeleted: (_) async {});

  int loadCalls = 0;

  @override
  Future<List<ManagedProvider>> load() async {
    loadCalls++;
    return [
      ManagedProvider(
        id: 'p1',
        name: 'Example',
        kind: ManagedProviderKind.apiBalance,
        adapterId: 'fake',
      ),
    ];
  }
}

class _FakeManagedProviderUsageCoordinator
    extends coordinator.ManagedProviderUsageCoordinator {
  _FakeManagedProviderUsageCoordinator()
    : super(
        providerRepository: _FakeManagedProviderRepository(),
        usageRepository: ManagedProviderUsageRepository(),
        registry: ManagedProviderUsageRegistry(),
        credentials: _EmptyCredentials(),
        http: _UnusedHttpClient(),
      );

  int loadCalls = 0;

  @override
  Future<coordinator.ManagedProviderUsageState> load() async {
    loadCalls++;
    return coordinator.ManagedProviderUsageState(
      providers: const [],
      snapshots: const {},
      generation: loadCalls,
      isRefreshing: false,
    );
  }
}

class _EmptyCredentials implements ProviderCredentialResolver {
  @override
  Future<ProviderCredentialScope?> resolve(ManagedProvider provider) async =>
      null;
}

class _EmptySecureStore implements SecureKeyValueStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

class _UnusedHttpClient implements ProviderUsageHttpClient {
  @override
  Future<ProviderUsageHttpResponse> send(ProviderUsageHttpRequest request) {
    throw UnsupportedError('not used');
  }
}
