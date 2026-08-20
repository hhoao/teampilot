import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/cubits/managed_provider_usage_cubit.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_usage_repository.dart';
import 'package:teampilot/services/provider_usage/managed_provider_secret_store.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_coordinator.dart'
    show ManagedProviderUsageCoordinator;
import 'package:teampilot/services/provider_usage/managed_provider_usage_registry.dart';

import '../support/in_memory_filesystem.dart';

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
  Object? error;
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
    if (error != null) throw error!;
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
  });

  test('loads cached snapshots before any refresh', () async {
    await providers.upsert(_provider());
    await usage.save(_ready());
    final cubit = ManagedProviderUsageCubit(coordinator: coordinator);
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.status, ManagedProviderUsageLoadStatus.ready);
    expect(cubit.state.snapshotFor('p1')!.measures.single.remaining, '12.50');
    expect(adapter.calls, 0);
  });

  test(
    'emits refreshing transitions and retains measures on failure',
    () async {
      await providers.upsert(_provider());
      await usage.save(_ready());
      adapter.error = const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.authenticationFailed,
      );
      final cubit = ManagedProviderUsageCubit(coordinator: coordinator);
      addTearDown(cubit.close);
      await cubit.load();
      final states = <ManagedProviderUsageState>[];
      final subscription = cubit.stream.listen(states.add);
      addTearDown(subscription.cancel);

      await cubit.refreshOne('p1');

      expect(states.any((state) => state.isRefreshing), isTrue);
      expect(cubit.state.isRefreshing, isFalse);
      expect(cubit.state.snapshotFor('p1')!.status, ProviderUsageStatus.error);
      expect(cubit.state.snapshotFor('p1')!.measures.single.remaining, '12.50');
    },
  );

  test(
    'testQuery updates only in-memory state with a secret-free typed error',
    () async {
      await providers.upsert(_provider());
      await usage.save(_ready());
      final cacheBefore = fs.files['/tp/usage-cache.json'];
      adapter.error = const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
      final cubit = ManagedProviderUsageCubit(coordinator: coordinator);
      addTearDown(cubit.close);
      await cubit.load();

      await cubit.testQuery('p1');

      expect(cubit.state.status, ManagedProviderUsageLoadStatus.error);
      expect(cubit.state.errorCode, ManagedProviderUsageErrorCode.queryFailed);
      expect(
        cubit.state.queryErrorCode,
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
      expect(cubit.state.errorMessage, isNot(contains('token')));
      expect(cubit.state.snapshotFor('p1')!.status, ProviderUsageStatus.error);
      expect(fs.files['/tp/usage-cache.json'], cacheBefore);
      expect((await usage.load()).single.status, ProviderUsageStatus.ready);
    },
  );

  test(
    'overlapping refreshOne and refreshAll keep the provider refreshing',
    () async {
      await providers.upsert(_provider());
      final gate = Completer<ProviderUsageSnapshot>();
      adapter.result = gate.future;
      final cubit = ManagedProviderUsageCubit(coordinator: coordinator);
      addTearDown(cubit.close);
      await cubit.load();
      final inconsistentStates = <ManagedProviderUsageState>[];
      final subscription = cubit.stream.listen((state) {
        if (!state.isRefreshing && state.refreshOperationCountFor('p1') > 0) {
          inconsistentStates.add(state);
        }
      });
      addTearDown(subscription.cancel);

      final one = cubit.refreshOne('p1');
      await Future<void>.delayed(Duration.zero);
      expect(adapter.calls, 1);
      final all = cubit.refreshAll();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isRefreshingProvider('p1'), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.refreshOperationCountFor('p1'), 2);
      gate.complete(_ready());
      await Future.wait([one, all]);

      expect(inconsistentStates, isEmpty);
      expect(cubit.state.isRefreshing, isFalse);
    },
  );

  test('refreshAll excludes disabled providers from transport work', () async {
    await providers.upsert(_provider());
    await providers.upsert(_provider(id: 'disabled', enabled: false));
    final cubit = ManagedProviderUsageCubit(coordinator: coordinator);
    addTearDown(cubit.close);
    await cubit.load();

    await cubit.refreshAll();

    expect(adapter.calls, 1);
    expect(
      cubit.state.snapshotFor('disabled')!.status,
      ProviderUsageStatus.unsupported,
    );
  });

  test(
    'duplicate ensureFresh calls share one refresh and fresh cache skips it',
    () async {
      await providers.upsert(_provider());
      final gate = Completer<ProviderUsageSnapshot>();
      adapter.result = gate.future;
      final cubit = ManagedProviderUsageCubit(
        coordinator: coordinator,
        now: () => DateTime.fromMillisecondsSinceEpoch(100),
      );
      addTearDown(cubit.close);
      await cubit.load();

      final first = cubit.ensureFresh('p1');
      final second = cubit.ensureFresh('p1');
      await Future<void>.delayed(Duration.zero);
      expect(adapter.calls, 1);
      gate.complete(_ready());
      await Future.wait([first, second]);
      expect(cubit.state.snapshotFor('p1')!.status, ProviderUsageStatus.ready);

      await cubit.ensureFresh('p1');
      expect(adapter.calls, 1);
    },
  );

  test(
    'cancelForProvider invalidates an in-flight ensureFresh Future',
    () async {
      await providers.upsert(_provider());
      final oldGate = Completer<ProviderUsageSnapshot>();
      adapter.result = oldGate.future;
      final cubit = ManagedProviderUsageCubit(coordinator: coordinator);
      addTearDown(cubit.close);
      await cubit.load();

      final oldEnsure = cubit.ensureFresh('p1');
      await Future<void>.delayed(Duration.zero);
      expect(adapter.calls, 1);

      await cubit.cancelForProvider('p1');
      final newGate = Completer<ProviderUsageSnapshot>();
      adapter.result = newGate.future;
      final newEnsure = cubit.ensureFresh('p1');
      await Future<void>.delayed(Duration.zero);
      expect(identical(newEnsure, oldEnsure), isFalse);
      expect(cubit.state.refreshOperationCountFor('p1'), 2);

      oldGate.complete(_ready(amount: '1.00'));
      await Future<void>.delayed(Duration.zero);
      expect(adapter.calls, 2);
      expect(cubit.state.refreshOperationCountFor('p1'), 1);

      newGate.complete(_ready(amount: '2.00'));
      expect(await oldEnsure, isNull);
      expect((await newEnsure)!.measures.single.remaining, '2.00');
      expect(cubit.state.isRefreshing, isFalse);
    },
  );

  test('removeProviders clears usage state after provider cleanup', () async {
    await providers.upsert(_provider());
    await usage.save(_ready());
    final cubit = ManagedProviderUsageCubit(coordinator: coordinator);
    addTearDown(cubit.close);
    await cubit.load();

    await providers.delete('p1');
    await cubit.removeProviders(['p1']);

    expect(cubit.state.snapshotFor('p1'), isNull);
  });

  test(
    'recreated provider does not reuse an invalidated ensureFresh future',
    () async {
      await providers.upsert(_provider());
      final oldGate = Completer<ProviderUsageSnapshot>();
      adapter.result = oldGate.future;
      final cubit = ManagedProviderUsageCubit(coordinator: coordinator);
      addTearDown(cubit.close);
      await cubit.load();

      final oldEnsure = cubit.ensureFresh('p1');
      await Future<void>.delayed(Duration.zero);
      expect(adapter.calls, 1);

      await providers.delete('p1');
      await cubit.removeProviders(['p1']);
      await providers.upsert(_provider());
      await cubit.reload();
      adapter.result = Future.value(_ready(amount: '2.00'));

      final newEnsure = cubit.ensureFresh('p1');
      expect(identical(newEnsure, oldEnsure), isFalse);
      oldGate.complete(_ready(amount: '1.00'));

      expect(await oldEnsure, isNull);
      expect((await newEnsure)!.measures.single.remaining, '2.00');
      expect(adapter.calls, 2);
    },
  );

  test(
    'an invalidated deleted refresh does not restore its old snapshot',
    () async {
      await providers.upsert(_provider());
      await usage.save(_ready());
      final gate = Completer<ProviderUsageSnapshot>();
      adapter.result = gate.future;
      final cubit = ManagedProviderUsageCubit(coordinator: coordinator);
      addTearDown(cubit.close);
      await cubit.load();

      final refresh = cubit.refreshOne('p1');
      await Future<void>.delayed(Duration.zero);
      await providers.delete('p1');
      gate.complete(_ready());

      expect(await refresh, isNull);
      expect(cubit.state.snapshotFor('p1'), isNull);
    },
  );

  test('refreshExpiredEnabled skips disabled and fresh snapshots', () async {
    await providers.upsert(_provider());
    await providers.upsert(_provider(id: 'disabled', enabled: false));
    await usage.save(_ready());
    final cubit = ManagedProviderUsageCubit(
      coordinator: coordinator,
      now: () => DateTime.fromMillisecondsSinceEpoch(100),
    );
    addTearDown(cubit.close);
    await cubit.load();

    await cubit.refreshExpiredEnabled();

    expect(adapter.calls, 0);
  });

  test('refreshExpiredEnabled queries stale enabled providers', () async {
    await providers.upsert(_provider());
    await usage.save(_ready(staleAt: 50));
    final cubit = ManagedProviderUsageCubit(
      coordinator: coordinator,
      now: () => DateTime.fromMillisecondsSinceEpoch(100),
    );
    addTearDown(cubit.close);
    await cubit.load();

    await cubit.refreshExpiredEnabled();

    expect(adapter.calls, 1);
  });

  test('closing during a blocked refresh does not emit or throw', () async {
    await providers.upsert(_provider());
    final gate = Completer<ProviderUsageSnapshot>();
    adapter.result = gate.future;
    final cubit = ManagedProviderUsageCubit(coordinator: coordinator);
    await cubit.load();
    final refresh = cubit.refreshOne('p1');
    await Future<void>.delayed(Duration.zero);
    await cubit.close();
    gate.complete(_ready());

    await expectLater(refresh, completes);
  });
}
