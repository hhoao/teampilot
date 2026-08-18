import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_usage_repository.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_coordinator.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_registry.dart';

import '../../support/in_memory_filesystem.dart';

class _FakeAdapter implements ManagedProviderUsageAdapter {
  _FakeAdapter(this.result, {this.error});

  final Future<ProviderUsageSnapshot> result;
  final Object? error;
  int calls = 0;

  @override
  String get id => 'fake';

  @override
  Future<ProviderUsageSnapshot> fetch(
    ManagedProvider provider, {
    required ProviderCredentialResolver credentials,
    required ProviderUsageHttpClient http,
    required DateTime now,
  }) {
    calls++;
    return _fetch();
  }

  Future<ProviderUsageSnapshot> _fetch() async {
    if (error != null) throw error!;
    return result;
  }
}

ManagedProvider _provider({bool enabled = true}) => ManagedProvider(
  id: 'p1',
  name: 'P1',
  kind: ManagedProviderKind.apiBalance,
  adapterId: 'fake',
  enabled: enabled,
);

ProviderUsageSnapshot _ready({String remaining = '12.50'}) =>
    ProviderUsageSnapshot(
      providerId: 'p1',
      status: ProviderUsageStatus.ready,
      measures: [
        ProviderUsageMeasure(
          label: 'Balance',
          kind: ProviderUsageMeasureKind.balance,
          remaining: remaining,
          unit: 'USD',
        ),
      ],
      fetchedAt: 1_700_000_000_000,
      staleAt: 1_700_003_600_000,
    );

void main() {
  late InMemoryFilesystem fs;
  late ManagedProviderRepository providers;
  late ManagedProviderUsageRepository usage;

  setUp(() {
    fs = InMemoryFilesystem();
    usage = ManagedProviderUsageRepository(
      fs: fs,
      cachePath: '/tp/usage-cache.json',
      now: () => 1_700_000_000_000,
    );
    providers = ManagedProviderRepository(
      fs: fs,
      configPath: '/tp/providers.json',
      onProvidersDeleted: usage.deleteMany,
    );
  });

  test('same provider has at most one in-flight request', () async {
    final gate = Completer<ProviderUsageSnapshot>();
    final adapter = _FakeAdapter(gate.future);
    await providers.upsert(_provider());
    final coordinator = ManagedProviderUsageCoordinator(
      providerRepository: providers,
      usageRepository: usage,
      registry: ManagedProviderUsageRegistry([adapter]),
      credentials: _NoCredentials(),
      http: _UnusedHttpClient(),
      now: () => DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
    );

    final first = coordinator.refreshOne('p1');
    final second = coordinator.refreshOne('p1');
    await Future<void>.delayed(Duration.zero);
    expect(adapter.calls, 1);
    gate.complete(_ready());
    await Future.wait([first, second]);
    expect(coordinator.snapshotFor('p1')!.status, ProviderUsageStatus.ready);
  });

  test(
    'refresh failure preserves old measures and maps typed errors',
    () async {
      await providers.upsert(_provider());
      await usage.save(_ready());
      final adapter = _FakeAdapter(
        Future.value(_ready()),
        error: const ManagedProviderUsageQueryError(
          ManagedProviderUsageQueryErrorCode.authenticationFailed,
        ),
      );
      final coordinator = ManagedProviderUsageCoordinator(
        providerRepository: providers,
        usageRepository: usage,
        registry: ManagedProviderUsageRegistry([adapter]),
        credentials: _NoCredentials(),
        http: _UnusedHttpClient(),
        now: () => DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
      );

      final result = await coordinator.refreshOne('p1');
      expect(result.status, ProviderUsageStatus.error);
      expect(result.lastErrorCode, 'authenticationFailed');
      expect(result.measures.single.remaining, '12.50');
      expect(result.lastErrorMessage, isNot(contains('token')));
    },
  );

  test(
    'disabled providers are not queried and receive unsupported state',
    () async {
      await providers.upsert(_provider(enabled: false));
      final adapter = _FakeAdapter(Future.value(_ready()));
      final coordinator = ManagedProviderUsageCoordinator(
        providerRepository: providers,
        usageRepository: usage,
        registry: ManagedProviderUsageRegistry([adapter]),
        credentials: _NoCredentials(),
        http: _UnusedHttpClient(),
        now: () => DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
      );

      final result = await coordinator.refreshAll();
      expect(result.single.status, ProviderUsageStatus.unsupported);
      expect(adapter.calls, 0);
    },
  );

  test('refreshAll is single-flight and aggregates providers', () async {
    await providers.upsert(_provider());
    final gate = Completer<ProviderUsageSnapshot>();
    final adapter = _FakeAdapter(gate.future);
    final coordinator = ManagedProviderUsageCoordinator(
      providerRepository: providers,
      usageRepository: usage,
      registry: ManagedProviderUsageRegistry([adapter]),
      credentials: _NoCredentials(),
      http: _UnusedHttpClient(),
      now: () => DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
    );

    final targeted = coordinator.refreshOne('p1');
    final first = coordinator.refreshAll();
    final second = coordinator.refreshAll();
    await Future<void>.delayed(Duration.zero);
    expect(adapter.calls, 1);
    gate.complete(_ready());
    expect((await targeted).status, ProviderUsageStatus.ready);
    expect((await first).single.status, ProviderUsageStatus.ready);
    expect((await second).single.providerId, 'p1');
  });

  test(
    'a disabled provider invalidates a blocked request before commit',
    () async {
      await providers.upsert(_provider());
      final gate = Completer<ProviderUsageSnapshot>();
      final adapter = _FakeAdapter(gate.future);
      final coordinator = ManagedProviderUsageCoordinator(
        providerRepository: providers,
        usageRepository: usage,
        registry: ManagedProviderUsageRegistry([adapter]),
        credentials: _NoCredentials(),
        http: _UnusedHttpClient(),
        now: () => DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
      );

      final pending = coordinator.refreshOne('p1');
      await Future<void>.delayed(Duration.zero);
      await providers.upsert(_provider(enabled: false));
      final disabled = await coordinator.refreshAll();
      expect(disabled.single.status, ProviderUsageStatus.unsupported);
      gate.complete(_ready());
      await pending;
      expect(
        coordinator.snapshotFor('p1')!.status,
        ProviderUsageStatus.unsupported,
      );
      expect(
        (await usage.load()).single.status,
        ProviderUsageStatus.unsupported,
      );
    },
  );

  test(
    'a credential change waits for the old request, then refreshes once',
    () async {
      await providers.upsert(_provider());
      final gate = Completer<ProviderUsageSnapshot>();
      final adapter = _FakeAdapter(gate.future);
      final coordinator = ManagedProviderUsageCoordinator(
        providerRepository: providers,
        usageRepository: usage,
        registry: ManagedProviderUsageRegistry([adapter]),
        credentials: _NoCredentials(),
        http: _UnusedHttpClient(),
        now: () => DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
      );

      final oldRequest = coordinator.refreshOne('p1');
      await Future<void>.delayed(Duration.zero);
      final externalProviders = ManagedProviderRepository(
        fs: fs,
        configPath: '/tp/providers.json',
        onProvidersDeleted: usage.deleteMany,
      );
      await externalProviders.upsert(
        _provider().copyWith(credentialRef: 'managed-provider:p1-new'),
      );
      final replacement = coordinator.refreshOne('p1');
      await Future<void>.delayed(Duration.zero);
      expect(adapter.calls, 1);
      gate.complete(_ready(remaining: '9.25'));
      final result = await replacement;
      await oldRequest;
      expect(result.status, ProviderUsageStatus.ready);
      expect(adapter.calls, 2);
      expect((await usage.load()).single.measures.single.remaining, '9.25');
    },
  );

  test('a deleted provider cannot commit a late result', () async {
    await providers.upsert(_provider());
    final gate = Completer<ProviderUsageSnapshot>();
    final adapter = _FakeAdapter(gate.future);
    final coordinator = ManagedProviderUsageCoordinator(
      providerRepository: providers,
      usageRepository: usage,
      registry: ManagedProviderUsageRegistry([adapter]),
      credentials: _NoCredentials(),
      http: _UnusedHttpClient(),
      now: () => DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
    );

    final pending = coordinator.refreshOne('p1');
    await Future<void>.delayed(Duration.zero);
    await providers.delete('p1');
    final deleted = await coordinator.refreshOne('p1');
    expect(deleted.status, ProviderUsageStatus.unsupported);
    gate.complete(_ready());
    await pending;
    expect(coordinator.snapshotFor('p1'), isNull);
    expect(await usage.load(), isEmpty);
  });
}

class _NoCredentials implements ProviderCredentialResolver {
  @override
  Future<ProviderCredentialScope?> resolve(ManagedProvider provider) async =>
      null;
}

class _UnusedHttpClient implements ProviderUsageHttpClient {
  @override
  Future<ProviderUsageHttpResponse> send(ProviderUsageHttpRequest request) {
    throw StateError('not used');
  }
}
