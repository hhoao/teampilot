import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/cubits/managed_provider_cubit.dart';
import 'package:teampilot/cubits/managed_provider_usage_cubit.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_usage_repository.dart';
import 'package:teampilot/services/provider_usage/managed_provider_secret_store.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_auto_refresh.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_coordinator.dart'
    show ManagedProviderUsageCoordinator;
import 'package:teampilot/services/provider_usage/managed_provider_usage_registry.dart';

import '../../support/in_memory_filesystem.dart';

ManagedProvider _provider({String id = 'p1', bool enabled = true}) =>
    ManagedProvider(
      id: id,
      name: id,
      kind: ManagedProviderKind.apiBalance,
      adapterId: 'fake',
      enabled: enabled,
    );

ProviderUsageSnapshot _ready({
  String id = 'p1',
  String amount = '12.50',
  int staleAt = 1_000,
}) => ProviderUsageSnapshot(
  providerId: id,
  status: ProviderUsageStatus.ready,
  measures: [
    ProviderUsageMeasure(
      label: 'Balance',
      kind: ProviderUsageMeasureKind.balance,
      remaining: amount,
      unit: 'USD',
    ),
  ],
  fetchedAt: 100,
  staleAt: staleAt,
);

class _Adapter implements ManagedProviderUsageAdapter {
  _Adapter(this.result);

  Future<ProviderUsageSnapshot> result;
  int calls = 0;

  @override
  String get id => 'fake';

  @override
  Future<ProviderUsageSnapshot> fetch(
    ManagedProvider provider, {
    required ProviderCredentialResolver credentials,
    required ProviderUsageHttpClient http,
    required DateTime now,
  }) async {
    calls++;
    return result;
  }
}

class _NoCredentials implements ProviderCredentialResolver {
  @override
  Future<ProviderCredentialScope> resolve(ManagedProvider provider) async =>
      ManagedProviderCredentialScope(const {});
}

class _NoHttp implements ProviderUsageHttpClient {
  @override
  Future<ProviderUsageHttpResponse> send(ProviderUsageHttpRequest request) {
    throw StateError('HTTP should be owned by the adapter test seam');
  }
}

void main() {
  late InMemoryFilesystem fs;
  late ManagedProviderRepository providers;
  late ManagedProviderUsageRepository usage;
  late _Adapter adapter;
  late ManagedProviderUsageCoordinator coordinator;
  late ManagedProviderUsageCubit usageCubit;
  late ManagedProviderCubit providerCubit;

  setUp(() async {
    fs = InMemoryFilesystem();
    usage = ManagedProviderUsageRepository(
      fs: fs,
      cachePath: '/tp/usage-cache.json',
      now: () => 100,
    );
    providers = ManagedProviderRepository(
      fs: fs,
      configPath: '/tp/providers.json',
      onProvidersDeleted: usage.deleteMany,
    );
    adapter = _Adapter(Future.value(_ready()));
    coordinator = ManagedProviderUsageCoordinator(
      providerRepository: providers,
      usageRepository: usage,
      registry: ManagedProviderUsageRegistry([adapter]),
      credentials: _NoCredentials(),
      http: _NoHttp(),
      now: () => DateTime.fromMillisecondsSinceEpoch(100),
    );
    usageCubit = ManagedProviderUsageCubit(
      coordinator: coordinator,
      now: () => DateTime.fromMillisecondsSinceEpoch(100),
    );
    providerCubit = ManagedProviderCubit(repository: providers);
    addTearDown(usageCubit.close);
    addTearDown(providerCubit.close);
  });

  test('start and tick refresh enabled providers while started', () async {
    await providers.upsert(_provider());
    await usage.save(_ready(staleAt: 50));
    await providerCubit.load();
    await usageCubit.load();
    late void Function() fire;
    var stopped = 0;
    final binder = ManagedProviderUsageAutoRefresh(
      usage: usageCubit,
      providers: providerCubit,
      startPeriodic: (callback, interval) {
        expect(interval, ManagedProviderUsageAutoRefresh.interval);
        expect(interval, const Duration(minutes: 10));
        fire = callback;
        return Object();
      },
      stopPeriodic: (_) => stopped++,
    );
    addTearDown(binder.dispose);

    binder.start();
    await Future<void>.delayed(Duration.zero);
    expect(adapter.calls, 1);

    fire();
    await Future<void>.delayed(Duration.zero);
    expect(adapter.calls, 2);

    binder.stop();
    expect(stopped, 1);
    fire();
    await Future<void>.delayed(Duration.zero);
    expect(adapter.calls, 2);
  });

  test('disabling a provider cancels its in-flight ensureFresh', () async {
    await providers.upsert(_provider());
    await usage.save(_ready(staleAt: 50));
    await providerCubit.load();
    await usageCubit.load();
    final binder = ManagedProviderUsageAutoRefresh(
      usage: usageCubit,
      providers: providerCubit,
      startPeriodic: (_, interval) {
        expect(interval, const Duration(minutes: 10));
        return Object();
      },
      stopPeriodic: (_) {},
    );
    addTearDown(binder.dispose);
    binder.start();

    final gate = Completer<ProviderUsageSnapshot>();
    adapter.result = gate.future;
    final pending = usageCubit.ensureFresh('p1');
    await Future<void>.delayed(Duration.zero);
    expect(adapter.calls, 1);

    await providerCubit.disable('p1');
    await Future<void>.delayed(Duration.zero);
    gate.complete(_ready(amount: '99.00'));
    expect(await pending, isNull);
    expect(
      usageCubit.state.snapshotFor('p1')?.measures.single.remaining,
      '12.50',
    );
  });
}
