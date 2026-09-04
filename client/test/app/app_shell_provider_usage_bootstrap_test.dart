import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/app/app_shell.dart';
import 'package:teampilot/cubits/managed_provider_cubit.dart';
import 'package:teampilot/cubits/managed_provider_usage_cubit.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_usage_repository.dart';
import 'package:teampilot/services/provider_usage/adapters/claude_official_subscription_auth.dart';
import 'package:teampilot/services/provider_usage/adapters/http_json_mapping_adapter.dart';
import 'package:teampilot/services/provider_usage/cli_credential_source.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_coordinator.dart'
    as coordinator;
import 'package:teampilot/services/provider_usage/managed_provider_usage_registry.dart';
import 'package:teampilot/services/provider_usage/managed_provider_secret_store.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  tearDown(AppStorage.resetForTesting);

  test('default registry exposes only the http-json adapter', () {
    final registry = buildDefaultManagedProviderUsageRegistry();

    expect(registry.adapterFor('http-json'), isA<HttpJsonMappingAdapter>());
    expect(registry.adapterFor('official-claude-subscription'), isNull);
    expect(registry.adapterFor('official-codex-subscription'), isNull);
  });

  test(
    'http-json adapter without cli credentials fails closed for cli sources',
    () async {
      final registry = buildDefaultManagedProviderUsageRegistry();
      final adapter = registry.adapterFor('http-json')!;

      await expectLater(
        adapter.fetch(
          ManagedProvider(
            id: 'cursor',
            name: 'Cursor',
            kind: ManagedProviderKind.subscriptionQuota,
            adapterId: 'http-json',
            endpointConfig: ManagedProviderEndpointConfig(
              url: 'https://cursor.com/api/usage-summary',
              credentialSource: 'cli:cursor-account',
              credentialName: 'Cookie',
              credentialTemplate:
                  'WorkosCursorSessionToken={accountId}::{accessToken}',
              windows: const [
                ManagedProviderUsageWindow(
                  label: 'Plan',
                  used: r'$.individualUsage.plan.totalPercentUsed',
                  unit: '%',
                ),
              ],
            ),
          ),
          credentials: _EmptyCredentials(),
          http: _UnusedHttpClient(),
          now: DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
        ),
        throwsA(
          isA<ManagedProviderUsageQueryError>().having(
            (error) => error.code,
            'code',
            ManagedProviderUsageQueryErrorCode.missingCredential,
          ),
        ),
      );
    },
  );

  test(
    'file-backed cli auth resolves credentials for http-json fetch',
    () async {
      final fs = InMemoryFilesystem();
      final registry = buildDefaultManagedProviderUsageRegistry(
        cliCredentials: CliCredentialSourceResolver(
          readers: {
            'claude': ClaudeOfficialSubscriptionAuthReader(
              fs: fs,
              basePath: '/tp',
            ),
          },
        ),
      );
      final adapter = registry.adapterFor('http-json')!;

      await expectLater(
        adapter.fetch(
          ManagedProvider(
            id: 'claude',
            name: 'Claude',
            kind: ManagedProviderKind.subscriptionQuota,
            adapterId: 'http-json',
            endpointConfig: ManagedProviderEndpointConfig(
              url: 'https://api.anthropic.com/api/oauth/usage',
              credentialSource: 'cli:claude-mp-p1',
              credentialField: 'accessToken',
              credentialName: 'Authorization',
              credentialPrefix: 'Bearer ',
              windows: const [
                ManagedProviderUsageWindow(
                  label: '5h',
                  used: r'$.five_hour.utilization',
                  unit: '%',
                ),
              ],
            ),
          ),
          credentials: _EmptyCredentials(),
          http: _UnusedHttpClient(),
          now: DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
        ),
        throwsA(
          isA<ManagedProviderUsageQueryError>().having(
            (error) => error.code,
            'code',
            ManagedProviderUsageQueryErrorCode.missingCredential,
          ),
        ),
      );
    },
  );

  test('default repositories follow the current AppStorage binding', () async {
    final firstFs = InMemoryFilesystem();
    final secondFs = InMemoryFilesystem();
    final firstPaths = const AppPaths('/managed-provider-home-one');
    final secondPaths = const AppPaths('/managed-provider-home-two');
    final provider = ManagedProvider(
      id: 'p1',
      name: 'One',
      kind: ManagedProviderKind.apiBalance,
      adapterId: 'http-json',
    );
    final snapshot = ProviderUsageSnapshot(
      providerId: 'p1',
      status: ProviderUsageStatus.ready,
      measures: [],
      fetchedAt: 1,
      staleAt: 2,
    );

    AppStorage.installForTesting(filesystem: firstFs, paths: firstPaths);
    final providerRepository = ManagedProviderRepository(
      onProvidersDeleted: (_) async {},
    );
    final usageRepository = ManagedProviderUsageRepository();
    await providerRepository.save([provider]);
    await usageRepository.save(snapshot);

    AppStorage.installForTesting(filesystem: secondFs, paths: secondPaths);
    expect(await providerRepository.load(), isEmpty);
    expect(await usageRepository.load(), isEmpty);

    AppStorage.installForTesting(filesystem: firstFs, paths: firstPaths);
    expect((await providerRepository.load()).single.id, 'p1');
    expect((await usageRepository.load()).single.providerId, 'p1');
  });

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

  test('control-plane close is owned, ordered, and idempotent', () async {
    final repository = _FakeManagedProviderRepository();
    final usageCoordinator = _FakeManagedProviderUsageCoordinator();
    final providerCubit = ManagedProviderCubit(repository: repository);
    final usageCubit = ManagedProviderUsageCubit(coordinator: usageCoordinator);
    var httpCloseCalls = 0;
    final controlPlane = ManagedProviderControlPlane(
      providerRepository: repository,
      usageRepository: ManagedProviderUsageRepository(),
      secretStore: ManagedProviderSecretStore(_EmptySecureStore()),
      usageRegistry: ManagedProviderUsageRegistry(),
      usageCoordinator: usageCoordinator,
      providerCubit: providerCubit,
      usageCubit: usageCubit,
      ownsProviderCubit: true,
      ownsUsageCubit: true,
      ownsUsageCoordinator: true,
      closeOwnedHttpClient: () async => httpCloseCalls++,
    );

    await controlPlane.close();
    await controlPlane.close();

    expect(usageCoordinator.closeCalls, 1);
    expect(providerCubit.isClosed, isTrue);
    expect(usageCubit.isClosed, isTrue);
    expect(httpCloseCalls, 1);
  });

  test(
    'control-plane lease closes on failure and transfers on success',
    () async {
      final repository = _FakeManagedProviderRepository();
      final usageCoordinator = _FakeManagedProviderUsageCoordinator();
      final providerCubit = ManagedProviderCubit(repository: repository);
      final usageCubit = ManagedProviderUsageCubit(
        coordinator: usageCoordinator,
      );
      var httpCloseCalls = 0;
      final controlPlane = ManagedProviderControlPlane(
        providerRepository: repository,
        usageRepository: ManagedProviderUsageRepository(),
        secretStore: ManagedProviderSecretStore(_EmptySecureStore()),
        usageRegistry: ManagedProviderUsageRegistry(),
        usageCoordinator: usageCoordinator,
        providerCubit: providerCubit,
        usageCubit: usageCubit,
        ownsProviderCubit: true,
        ownsUsageCubit: true,
        ownsUsageCoordinator: true,
        closeOwnedHttpClient: () async => httpCloseCalls++,
      );
      final lease = ManagedProviderControlPlaneLease(controlPlane);

      await lease.closeIfOwned();
      await lease.closeIfOwned();

      expect(usageCoordinator.closeCalls, 1);
      expect(httpCloseCalls, 1);

      final transferredCoordinator = _FakeManagedProviderUsageCoordinator();
      final transferredProviderCubit = ManagedProviderCubit(
        repository: repository,
      );
      final transferredUsageCubit = ManagedProviderUsageCubit(
        coordinator: transferredCoordinator,
      );
      final transferredControlPlane = ManagedProviderControlPlane(
        providerRepository: repository,
        usageRepository: ManagedProviderUsageRepository(),
        secretStore: ManagedProviderSecretStore(_EmptySecureStore()),
        usageRegistry: ManagedProviderUsageRegistry(),
        usageCoordinator: transferredCoordinator,
        providerCubit: transferredProviderCubit,
        usageCubit: transferredUsageCubit,
        ownsProviderCubit: true,
        ownsUsageCubit: true,
        ownsUsageCoordinator: true,
      );
      final transferredLease = ManagedProviderControlPlaneLease(
        transferredControlPlane,
      )..transferOwnership();

      await transferredLease.closeIfOwned();
      expect(transferredCoordinator.closeCalls, 0);
      await transferredControlPlane.close();
      expect(transferredCoordinator.closeCalls, 1);
    },
  );
}

class _FakeManagedProviderRepository extends ManagedProviderRepository {
  _FakeManagedProviderRepository() : super(onProvidersDeleted: (_) async {});

  int loadCalls = 0;
  int closeCalls = 0;

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
  int closeCalls = 0;

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

  @override
  Future<void> close() async {
    closeCalls++;
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