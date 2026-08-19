import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_usage_repository.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_coordinator.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_registry.dart';
import 'package:teampilot/services/storage/app_storage.dart';

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

class _QueuedAdapter implements ManagedProviderUsageAdapter {
  _QueuedAdapter(this.results);

  final List<Future<ProviderUsageSnapshot>> results;
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
    final result = results[calls];
    calls++;
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

  tearDown(AppStorage.resetForTesting);

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
    'storage context invalidation prevents an old request from writing to the new home',
    () async {
      final firstFs = InMemoryFilesystem();
      final secondFs = InMemoryFilesystem();
      final firstPaths = const AppPaths('/managed-provider-context-one');
      final secondPaths = const AppPaths('/managed-provider-context-two');
      final gate = Completer<ProviderUsageSnapshot>();
      final adapter = _FakeAdapter(gate.future);

      AppStorage.installForTesting(filesystem: firstFs, paths: firstPaths);
      final dynamicUsage = ManagedProviderUsageRepository();
      final dynamicProviders = ManagedProviderRepository(
        onProvidersDeleted: dynamicUsage.deleteMany,
      );
      await dynamicProviders.upsert(_provider());

      AppStorage.installForTesting(filesystem: secondFs, paths: secondPaths);
      await dynamicProviders.upsert(_provider());

      AppStorage.installForTesting(filesystem: firstFs, paths: firstPaths);
      final coordinator = ManagedProviderUsageCoordinator(
        providerRepository: dynamicProviders,
        usageRepository: dynamicUsage,
        registry: ManagedProviderUsageRegistry([adapter]),
        credentials: _NoCredentials(),
        http: _UnusedHttpClient(),
        now: () => DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
      );

      final oldRequest = coordinator.refreshOne('p1');
      await Future<void>.delayed(Duration.zero);
      expect(adapter.calls, 1);

      await coordinator.invalidateForStorageContextChange();
      AppStorage.installForTesting(filesystem: secondFs, paths: secondPaths);
      gate.complete(_ready(remaining: '1.75'));

      await expectLater(
        oldRequest,
        throwsA(
          isA<ManagedProviderUsageInvalidated>().having(
            (error) => error.code,
            'code',
            ManagedProviderUsageInvalidationCode.refreshCancelled,
          ),
        ),
      );
      expect(await dynamicUsage.load(), isEmpty);
    },
  );

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
    'queryOne normalizes transient results without changing the usage cache',
    () async {
      await providers.upsert(_provider());
      await usage.save(_ready());
      final cacheBefore = fs.files['/tp/usage-cache.json'];
      final adapter = _FakeAdapter(
        Future.value(_ready(remaining: '99.999999999999')),
      );
      final coordinator = ManagedProviderUsageCoordinator(
        providerRepository: providers,
        usageRepository: usage,
        registry: ManagedProviderUsageRegistry([adapter]),
        credentials: _NoCredentials(),
        http: _UnusedHttpClient(),
        now: () => DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
      );

      final result = await coordinator.queryOne('p1');

      expect(result.status, ProviderUsageStatus.ready);
      expect(result.providerId, 'p1');
      expect(result.measures.single.remaining, '99.999999999999');
      expect(coordinator.snapshotFor('p1')!.measures.single.remaining, '12.50');
      expect(fs.files['/tp/usage-cache.json'], cacheBefore);
      expect((await usage.load()).single.measures.single.remaining, '12.50');
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
      await expectLater(
        pending,
        throwsA(
          isA<ManagedProviderUsageInvalidated>().having(
            (error) => error.code,
            'code',
            ManagedProviderUsageInvalidationCode.providerChanged,
          ),
        ),
      );
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
      final oldInvalidation = expectLater(
        oldRequest,
        throwsA(
          isA<ManagedProviderUsageInvalidated>().having(
            (error) => error.code,
            'code',
            ManagedProviderUsageInvalidationCode.providerChanged,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(adapter.calls, 1);
      gate.complete(_ready(remaining: '9.25'));
      final result = await replacement;
      await oldInvalidation;
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
    gate.complete(_ready());
    await expectLater(
      pending,
      throwsA(
        isA<ManagedProviderUsageInvalidated>().having(
          (error) => error.code,
          'code',
          ManagedProviderUsageInvalidationCode.providerDeleted,
        ),
      ),
    );
    expect(coordinator.providers, isEmpty);
    expect(coordinator.snapshotFor('p1'), isNull);
    expect(await usage.load(), isEmpty);
  });

  test('cancel then refreshOne queues a committed successor', () async {
    await providers.upsert(_provider());
    final firstGate = Completer<ProviderUsageSnapshot>();
    final secondGate = Completer<ProviderUsageSnapshot>();
    final adapter = _QueuedAdapter([firstGate.future, secondGate.future]);
    final coordinator = ManagedProviderUsageCoordinator(
      providerRepository: providers,
      usageRepository: usage,
      registry: ManagedProviderUsageRegistry([adapter]),
      credentials: _NoCredentials(),
      http: _UnusedHttpClient(),
      now: () => DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
    );

    final cancelled = coordinator.refreshOne('p1');
    await Future<void>.delayed(Duration.zero);
    await coordinator.cancelForProvider('p1');
    final shared = coordinator.refreshOne('p1');
    await Future<void>.delayed(Duration.zero);
    expect(adapter.calls, 1);
    firstGate.complete(_ready(remaining: '11.00'));
    await expectLater(
      cancelled,
      throwsA(
        isA<ManagedProviderUsageInvalidated>().having(
          (error) => error.code,
          'code',
          ManagedProviderUsageInvalidationCode.refreshCancelled,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(adapter.calls, 2);
    secondGate.complete(_ready(remaining: '8.50'));
    final result = await shared;
    expect(result.status, ProviderUsageStatus.ready);
    expect(coordinator.snapshotFor('p1')!.measures.single.remaining, '8.50');
    expect((await usage.load()).single.measures.single.remaining, '8.50');
  });

  test('cancellation linearizes behind a blocked commit', () async {
    final blockingUsage = _BlockingUsageRepository(fs: fs);
    await providers.upsert(_provider());
    final adapter = _QueuedAdapter([
      Future.value(_ready(remaining: '11.00')),
      Future.value(_ready(remaining: '8.50')),
    ]);
    final coordinator = ManagedProviderUsageCoordinator(
      providerRepository: providers,
      usageRepository: blockingUsage,
      registry: ManagedProviderUsageRegistry([adapter]),
      credentials: _NoCredentials(),
      http: _UnusedHttpClient(),
      now: () => DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
    );

    final oldResult = coordinator.refreshOne('p1');
    await blockingUsage.saveStarted.future;
    var cancellationCompleted = false;
    final cancellation = coordinator.cancelForProvider('p1');
    cancellation.then((_) => cancellationCompleted = true);
    await Future<void>.delayed(Duration.zero);
    expect(cancellationCompleted, isFalse);
    final oldInvalidation = expectLater(
      oldResult,
      throwsA(
        isA<ManagedProviderUsageInvalidated>().having(
          (error) => error.code,
          'code',
          ManagedProviderUsageInvalidationCode.refreshCancelled,
        ),
      ),
    );
    blockingUsage.release.complete();
    await cancellation;
    await oldInvalidation;
    expect(adapter.calls, 1);
    expect(await blockingUsage.load(), isEmpty);

    final successor = await coordinator.refreshOne('p1');
    expect(successor.measures.single.remaining, '8.50');
    expect(adapter.calls, 2);
    expect(
      (await blockingUsage.load()).single.measures.single.remaining,
      '8.50',
    );
  });

  test(
    'save failure after cancellation intent becomes typed invalidation',
    () async {
      final failingUsage = _ThrowingUsageRepository(fs: fs);
      await providers.upsert(_provider());
      final coordinator = ManagedProviderUsageCoordinator(
        providerRepository: providers,
        usageRepository: failingUsage,
        registry: ManagedProviderUsageRegistry([
          _FakeAdapter(Future.value(_ready())),
        ]),
        credentials: _NoCredentials(),
        http: _UnusedHttpClient(),
        now: () => DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
      );

      final oldResult = coordinator.refreshOne('p1');
      await failingUsage.saveStarted.future;
      final cancellation = coordinator.cancelForProvider('p1');
      failingUsage.release.complete();

      await expectLater(
        oldResult,
        throwsA(
          isA<ManagedProviderUsageInvalidated>().having(
            (error) => error.code,
            'code',
            ManagedProviderUsageInvalidationCode.refreshCancelled,
          ),
        ),
      );
      await cancellation;
      expect(coordinator.snapshotFor('p1'), isNull);
      expect(await failingUsage.load(), isEmpty);
    },
  );

  test('ordinary save failure is a redacted typed persistence error', () async {
    final failingUsage = _ThrowingUsageRepository(fs: fs)..release.complete();
    await providers.upsert(_provider());
    final coordinator = ManagedProviderUsageCoordinator(
      providerRepository: providers,
      usageRepository: failingUsage,
      registry: ManagedProviderUsageRegistry([
        _FakeAdapter(Future.value(_ready())),
      ]),
      credentials: _NoCredentials(),
      http: _UnusedHttpClient(),
      now: () => DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
    );

    await expectLater(
      coordinator.refreshOne('p1'),
      throwsA(
        isA<ManagedProviderUsagePersistenceError>().having(
          (error) => error.message,
          'message',
          isNot(contains('/tp/usage-cache.json')),
        ),
      ),
    );
    expect(coordinator.snapshotFor('p1'), isNull);
    expect(await failingUsage.load(), isEmpty);
  });

  test(
    'disabled snapshot save is serialized against re-enable mutation',
    () async {
      final blockingUsage = _BlockingUsageRepository(fs: fs);
      final disabledProviders = ManagedProviderRepository(
        fs: fs,
        configPath: '/tp/providers.json',
        onProvidersDeleted: blockingUsage.deleteMany,
      );
      await disabledProviders.upsert(_provider(enabled: false));
      final coordinator = ManagedProviderUsageCoordinator(
        providerRepository: disabledProviders,
        usageRepository: blockingUsage,
        registry: ManagedProviderUsageRegistry(),
        credentials: _NoCredentials(),
        http: _UnusedHttpClient(),
        now: () => DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
      );

      final refresh = coordinator.refreshAll();
      await blockingUsage.saveStarted.future;
      var reenableCompleted = false;
      final reenable = disabledProviders.upsert(_provider());
      reenable.then((_) => reenableCompleted = true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(reenableCompleted, isFalse);
      blockingUsage.release.complete();
      await refresh;
      await reenable;
      expect((await disabledProviders.load()).single.enabled, isTrue);
      expect(
        (await blockingUsage.load()).single.status,
        ProviderUsageStatus.unsupported,
      );
    },
  );
}

class _BlockingUsageRepository extends ManagedProviderUsageRepository {
  _BlockingUsageRepository({required InMemoryFilesystem fs})
    : super(fs: fs, cachePath: '/tp/usage-cache.json');

  final saveStarted = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> saveIf(
    ProviderUsageSnapshot snapshot, {
    required bool Function() shouldCommit,
  }) async {
    if (!saveStarted.isCompleted) saveStarted.complete();
    await release.future;
    return super.saveIf(snapshot, shouldCommit: shouldCommit);
  }
}

class _ThrowingUsageRepository extends ManagedProviderUsageRepository {
  _ThrowingUsageRepository({required InMemoryFilesystem fs})
    : super(fs: fs, cachePath: '/tp/usage-cache.json');

  final saveStarted = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> saveIf(
    ProviderUsageSnapshot snapshot, {
    required bool Function() shouldCommit,
  }) async {
    if (!saveStarted.isCompleted) saveStarted.complete();
    await release.future;
    throw StateError('storage path and secret must not escape');
  }
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
