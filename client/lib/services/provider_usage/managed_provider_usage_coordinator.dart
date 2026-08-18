import 'dart:async';

import '../../models/managed_provider.dart';
import '../../models/provider_usage_snapshot.dart';
import '../../repositories/managed_provider_repository.dart';
import '../../repositories/managed_provider_usage_repository.dart';
import 'managed_provider_usage_adapter.dart';
import 'managed_provider_usage_registry.dart';

enum ManagedProviderUsageInvalidationCode {
  providerDeleted,
  providerChanged,
  refreshCancelled,
}

/// Secret-free outcome for a refresh invalidated by lifecycle/configuration
/// changes. An old request for a deleted provider can never masquerade as a
/// successful snapshot.
class ManagedProviderUsageInvalidated implements Exception {
  const ManagedProviderUsageInvalidated({
    required this.providerId,
    required this.code,
  });

  final String providerId;
  final ManagedProviderUsageInvalidationCode code;

  String get message => 'Managed provider usage refresh ${code.name}.';

  @override
  String toString() => 'ManagedProviderUsageInvalidated: $message';
}

enum ManagedProviderUsagePersistenceErrorCode { saveFailed }

/// Secret-free, typed failures while persisting a usage snapshot.
class ManagedProviderUsagePersistenceError implements Exception {
  const ManagedProviderUsagePersistenceError({
    required this.providerId,
    required this.code,
  });

  final String providerId;
  final ManagedProviderUsagePersistenceErrorCode code;

  String get message => 'Managed provider usage persistence ${code.name}.';

  @override
  String toString() => 'ManagedProviderUsagePersistenceError: $message';
}

/// Immutable view consumed by a future Cubit or status-bar presenter.
class ManagedProviderUsageState {
  ManagedProviderUsageState({
    required Iterable<ManagedProvider> providers,
    required Map<String, ProviderUsageSnapshot> snapshots,
    required this.generation,
    required this.isRefreshing,
  }) : providers = List.unmodifiable(providers),
       snapshots = Map.unmodifiable(snapshots);

  final List<ManagedProvider> providers;
  final Map<String, ProviderUsageSnapshot> snapshots;
  final int generation;
  final bool isRefreshing;
}

/// Coordinates cached usage and network refreshes independently of any UI.
class ManagedProviderUsageCoordinator {
  static const queryTimeout = Duration(seconds: 30);

  ManagedProviderUsageCoordinator({
    required ManagedProviderRepository providerRepository,
    required ManagedProviderUsageRepository usageRepository,
    required ManagedProviderUsageRegistry registry,
    required ProviderCredentialResolver credentials,
    required ProviderUsageHttpClient http,
    DateTime Function()? now,
  }) : _providerRepository = providerRepository,
       _usageRepository = usageRepository,
       _registry = registry,
       _credentials = credentials,
       _http = http,
       _now = now ?? DateTime.now;

  final ManagedProviderRepository _providerRepository;
  final ManagedProviderUsageRepository _usageRepository;
  final ManagedProviderUsageRegistry _registry;
  final ProviderCredentialResolver _credentials;
  final ProviderUsageHttpClient _http;
  final DateTime Function() _now;

  final Map<String, ManagedProvider> _providers = {};
  final Map<String, ProviderUsageSnapshot> _snapshots = {};
  final Map<String, _PendingRefresh> _pending = {};
  final Map<String, Future<ProviderUsageSnapshot>> _transientQueries = {};
  final Map<String, _ProviderCommitGate> _commitGates = {};
  final Map<String, int> _tokens = {};
  int _generation = 0;
  int _storageContextGeneration = 0;
  bool _loaded = false;
  bool _closed = false;
  Future<ManagedProviderUsageState>? _loadFlight;
  Future<List<ProviderUsageSnapshot>>? _refreshAllFlight;

  ManagedProviderUsageState get state => ManagedProviderUsageState(
    providers: _providers.values,
    snapshots: _snapshots,
    generation: _generation,
    isRefreshing: _pending.isNotEmpty || _refreshAllFlight != null,
  );

  List<ManagedProvider> get providers => List.unmodifiable(_providers.values);

  Map<String, ProviderUsageSnapshot> get snapshots =>
      Map.unmodifiable(_snapshots);

  ProviderUsageSnapshot? snapshotFor(String providerId) =>
      _snapshots[providerId.trim()];

  /// Loads usage cache before the provider catalog and never performs HTTP.
  Future<ManagedProviderUsageState> load() {
    if (_closed) return Future<ManagedProviderUsageState>.value(state);
    final existing = _loadFlight;
    if (existing != null) return existing;
    final contextGeneration = _storageContextGeneration;
    final flight = _loadCacheAndProviders(contextGeneration);
    _loadFlight = flight;
    return flight.whenComplete(() {
      if (identical(_loadFlight, flight)) _loadFlight = null;
    });
  }

  Future<ManagedProviderUsageState> _loadCacheAndProviders(
    int contextGeneration,
  ) async {
    final cached = await _usageRepository.load();
    final configured = await _providerRepository.load();
    if (contextGeneration != _storageContextGeneration || _closed) {
      return state;
    }
    _generation++;
    _providers
      ..clear()
      ..addEntries(
        configured
            .where((provider) => provider.id.trim().isNotEmpty)
            .map((provider) => MapEntry(provider.id.trim(), provider)),
      );
    _snapshots
      ..clear()
      ..addEntries(
        cached
            .where((snapshot) => _providers.containsKey(snapshot.providerId))
            .map((snapshot) => MapEntry(snapshot.providerId, snapshot)),
      );
    for (final provider in _providers.values) {
      if (!provider.enabled) {
        _snapshots[provider.id] = _unsupportedSnapshot(
          provider.id,
          _snapshots[provider.id],
        );
      }
    }
    _loaded = true;
    return state;
  }

  /// Refreshes one provider. Concurrent calls for the same provider share a
  /// Future, while calls for different providers run independently.
  Future<ProviderUsageSnapshot> refreshOne(String providerId) async {
    if (_closed) return _unsupportedSnapshot(providerId.trim(), null);
    final storageContextGeneration = _storageContextGeneration;
    await _ensureLoaded();
    _ensureStorageContextCurrent(
      storageContextGeneration,
      providerId: providerId.trim(),
    );
    await _synchronizeProviders();
    _ensureStorageContextCurrent(storageContextGeneration);
    final id = providerId.trim();
    final provider = _providers[id];
    if (provider == null) return _unsupportedSnapshot(id, _snapshots[id]);
    return _refreshLoadedProvider(
      provider,
      _generation,
      storageContextGeneration: storageContextGeneration,
    );
  }

  /// Queries a provider for an ephemeral validation result. Unlike
  /// [refreshOne], this method never writes the usage cache or replaces the
  /// coordinator's persisted snapshot. It is intended for editor "test
  /// query" actions where a user has not saved the provider yet.
  Future<ProviderUsageSnapshot> queryOne(String providerId) async {
    if (_closed) return _unsupportedSnapshot(providerId.trim(), null);
    final storageContextGeneration = _storageContextGeneration;
    await _ensureLoaded();
    _ensureStorageContextCurrent(storageContextGeneration);
    await _synchronizeProviders();
    _ensureStorageContextCurrent(storageContextGeneration);
    final id = providerId.trim();
    final provider = _providers[id];
    if (provider == null || !provider.enabled) {
      return _unsupportedSnapshot(id, _snapshots[id]);
    }
    return queryProvider(provider);
  }

  /// Queries an in-memory Provider draft without reading or writing the
  /// persisted catalog/cache. Calls for the same Provider are coalesced and
  /// serialized with ordinary refresh work.
  Future<ProviderUsageSnapshot> queryProvider(ManagedProvider provider) {
    final id = provider.id.trim();
    if (_closed) {
      return Future<ProviderUsageSnapshot>.value(
        _errorSnapshot(
          id,
          _snapshots[id],
          ManagedProviderUsageQueryErrorCode.networkFailed,
        ),
      );
    }
    final existing = _transientQueries[id];
    if (existing != null) return existing;
    final pendingRefresh = _pending[id];
    if (pendingRefresh != null) {
      return pendingRefresh.future.then(
        (_) => queryProvider(provider),
        onError: (Object _, StackTrace __) => queryProvider(provider),
      );
    }
    final contextGeneration = _storageContextGeneration;
    final future = _queryProviderInternal(provider, contextGeneration);
    _transientQueries[id] = future;
    future.then<void>(
      (_) {
        if (identical(_transientQueries[id], future)) {
          _transientQueries.remove(id);
        }
      },
      onError: (Object _, StackTrace __) {
        if (identical(_transientQueries[id], future)) {
          _transientQueries.remove(id);
        }
      },
    );
    return future;
  }

  Future<ProviderUsageSnapshot> _queryProviderInternal(
    ManagedProvider provider,
    int storageContextGeneration,
  ) async {
    final id = provider.id.trim();
    final previous = _snapshots[id];
    if (!provider.enabled) return _unsupportedSnapshot(id, previous);

    try {
      final adapter = _registry.adapterFor(provider.adapterId);
      if (adapter == null) {
        throw const ManagedProviderUsageQueryError(
          ManagedProviderUsageQueryErrorCode.unsupported,
        );
      }
      final result = await adapter
          .fetch(provider, credentials: _credentials, http: _http, now: _now())
          .timeout(queryTimeout);
      _ensureStorageContextCurrent(storageContextGeneration);
      return result.copyWith(providerId: id, status: ProviderUsageStatus.ready);
    } on ManagedProviderUsageQueryError catch (error) {
      return _errorSnapshot(id, previous, error.code);
    } on ManagedProviderUsageInvalidated {
      rethrow;
    } on Object {
      return _errorSnapshot(
        id,
        previous,
        ManagedProviderUsageQueryErrorCode.networkFailed,
      );
    }
  }

  /// Refreshes all configured providers through the same per-provider single-
  /// flight map used by targeted refreshes.
  Future<List<ProviderUsageSnapshot>> refreshAll() {
    if (_closed) return Future<List<ProviderUsageSnapshot>>.value(const []);
    final existing = _refreshAllFlight;
    if (existing != null) return existing;
    final flight = _refreshAllInternal();
    _refreshAllFlight = flight;
    return flight.whenComplete(() {
      if (identical(_refreshAllFlight, flight)) _refreshAllFlight = null;
    });
  }

  Future<List<ProviderUsageSnapshot>> _refreshAllInternal() async {
    final storageContextGeneration = _storageContextGeneration;
    await _ensureLoaded();
    _ensureStorageContextCurrent(storageContextGeneration);
    await _synchronizeProviders();
    _ensureStorageContextCurrent(storageContextGeneration);
    // Do not advance the generation merely because the caller chose the
    // aggregate entry point. The per-provider pending future is shared with
    // targeted refreshes, so this must not create a duplicate request.
    final generation = _generation;
    final current = _providers.values.toList(growable: false);
    final results = await Future.wait(
      current.map(
        (provider) =>
            _refreshForAll(provider, generation, storageContextGeneration),
      ),
    );
    return [
      for (final result in results)
        if (result != null) result,
    ];
  }

  Future<ProviderUsageSnapshot?> _refreshForAll(
    ManagedProvider provider,
    int generation,
    int storageContextGeneration,
  ) async {
    try {
      return await _refreshLoadedProvider(
        provider,
        generation,
        storageContextGeneration: storageContextGeneration,
      );
    } on ManagedProviderUsageInvalidated {
      if (storageContextGeneration != _storageContextGeneration) rethrow;
      final current = _providers[provider.id];
      if (current == null) return null;
      if (!current.enabled) {
        return _completeDisabledProvider(
          current,
          generation: _generation,
          storageContextGeneration: storageContextGeneration,
          mutationRevision: _providerRepository.mutationRevision,
        );
      }
      // A cancellation or configuration change during all-refresh is retried
      // through the same serialized pending map, never concurrently.
      return _refreshLoadedProvider(
        current,
        _generation,
        storageContextGeneration: storageContextGeneration,
      );
    }
  }

  /// Invalidates an in-flight provider request. Dart HTTP transports may not
  /// be cancellable, so the generation/token check discards its result.
  Future<void> cancelForProvider(String providerId) async {
    if (_closed) return;
    final id = providerId.trim();
    if (id.isEmpty) return;
    // Record cancellation intent synchronously so a commit that is currently
    // awaiting cache I/O can detect it when the await returns. The gate below
    // then linearizes cancellation completion with that commit.
    _tokens[id] = (_tokens[id] ?? 0) + 1;
    _pending[id]?.cancelled = true;
    await _commitGates.putIfAbsent(id, _ProviderCommitGate.new).run<void>(
      () async {
        // Keep the tombstone until the transport Future completes. Removing
        // it here would allow a second transport while cancellation is still
        // linearizing with an in-flight commit.
      },
    );
  }

  /// Invalidates all refreshes and cache loads before the home storage context
  /// is rebound. The underlying HTTP transport is intentionally not cancelled;
  /// its result is rejected by the context generation/token checks and cannot
  /// be written into the newly bound context.
  Future<void> invalidateForStorageContextChange() async {
    if (_closed) return;
    _storageContextGeneration++;
    _generation++;
    _loaded = false;
    _refreshAllFlight = null;
    _transientQueries.clear();
    for (final entry in _pending.entries) {
      entry.value.cancelled = true;
      _tokens[entry.key] = (_tokens[entry.key] ?? 0) + 1;
    }
    _loadFlight = null;
    final gates = [
      for (final id in _pending.keys)
        _commitGates
            .putIfAbsent(id, _ProviderCommitGate.new)
            .run<void>(() async {}),
    ];
    await Future.wait(gates);
  }

  /// Stops accepting new work and invalidates all in-flight results.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _storageContextGeneration++;
    _generation++;
    _loaded = false;
    _refreshAllFlight = null;
    _transientQueries.clear();
    _loadFlight = null;
    for (final entry in _pending.entries) {
      entry.value.cancelled = true;
      _tokens[entry.key] = (_tokens[entry.key] ?? 0) + 1;
    }
    final gates = [
      for (final id in _pending.keys)
        _commitGates
            .putIfAbsent(id, _ProviderCommitGate.new)
            .run<void>(() async {}),
    ];
    await Future.wait(gates);
  }

  Future<ProviderUsageSnapshot> _refreshLoadedProvider(
    ManagedProvider provider,
    int generation, {
    required int storageContextGeneration,
  }) {
    final id = provider.id;
    _ensureStorageContextCurrent(storageContextGeneration, providerId: id);
    if (!provider.enabled) {
      return _completeDisabledProvider(
        provider,
        generation: generation,
        storageContextGeneration: storageContextGeneration,
        mutationRevision: _providerRepository.mutationRevision,
      );
    }
    final transientQuery = _transientQueries[id];
    if (transientQuery != null) {
      return transientQuery.then(
        (_) => _refreshLoadedProvider(
          provider,
          generation,
          storageContextGeneration: storageContextGeneration,
        ),
        onError: (Object _, StackTrace __) => _refreshLoadedProvider(
          provider,
          generation,
          storageContextGeneration: storageContextGeneration,
        ),
      );
    }
    final previousPending = _pending[id];
    if (previousPending != null) {
      if (previousPending.cancelled) {
        return previousPending.future.then(
          (_) => _startSuccessorAfterPending(id, storageContextGeneration),
          onError: (Object _, StackTrace __) =>
              _startSuccessorAfterPending(id, storageContextGeneration),
        );
      }
      if (previousPending.provider == provider) {
        return previousPending.future;
      }
      // Configuration changed while the old request was in flight. The
      // transport may not be cancellable, so wait for it before starting the
      // replacement; this preserves one underlying request per provider.
      return previousPending.future.then(
        (_) => _startSuccessorAfterPending(id, storageContextGeneration),
        onError: (Object _, StackTrace __) =>
            _startSuccessorAfterPending(id, storageContextGeneration),
      );
    }

    final token = (_tokens[id] ?? 0) + 1;
    _tokens[id] = token;
    final future = _executeRefresh(
      provider,
      generation,
      token,
      storageContextGeneration,
      _providerRepository.mutationRevision,
    );
    final pending = _PendingRefresh(
      provider: provider,
      generation: generation,
      token: token,
      future: future,
    );
    _pending[id] = pending;
    future.then<void>(
      (_) {
        if (identical(_pending[id], pending)) _pending.remove(id);
      },
      onError: (Object _, StackTrace __) {
        if (identical(_pending[id], pending)) _pending.remove(id);
      },
    );
    return future;
  }

  Future<ProviderUsageSnapshot> _startSuccessorAfterPending(
    String id,
    int storageContextGeneration,
  ) async {
    _ensureStorageContextCurrent(storageContextGeneration);
    await _synchronizeProviders();
    _ensureStorageContextCurrent(storageContextGeneration);
    final current = _providers[id];
    if (current == null) {
      _throwInvalidated(
        id,
        ManagedProviderUsageInvalidationCode.providerDeleted,
      );
    }
    if (!current.enabled) {
      return _completeDisabledProvider(
        current,
        generation: _generation,
        storageContextGeneration: storageContextGeneration,
        mutationRevision: _providerRepository.mutationRevision,
      );
    }
    return _refreshLoadedProvider(
      current,
      _generation,
      storageContextGeneration: storageContextGeneration,
    );
  }

  Future<ProviderUsageSnapshot> _completeDisabledProvider(
    ManagedProvider provider, {
    required int generation,
    required int storageContextGeneration,
    required int mutationRevision,
  }) async {
    final result = _unsupportedSnapshot(provider.id, _snapshots[provider.id]);
    return _commitResult(
      provider: provider,
      generation: generation,
      storageContextGeneration: storageContextGeneration,
      mutationRevision: mutationRevision,
      result: result,
      previous: _snapshots[provider.id],
      requiresEnabled: false,
    );
  }

  Future<ProviderUsageSnapshot> _executeRefresh(
    ManagedProvider provider,
    int generation,
    int token,
    int storageContextGeneration,
    int mutationRevision,
  ) async {
    final previous = _snapshots[provider.id];
    if (!provider.enabled) {
      final result = _unsupportedSnapshot(provider.id, previous);
      return _commitResult(
        provider: provider,
        generation: generation,
        token: token,
        storageContextGeneration: storageContextGeneration,
        mutationRevision: mutationRevision,
        result: result,
        previous: previous,
        requiresEnabled: false,
      );
    }

    ProviderUsageSnapshot result;
    try {
      final adapter = _registry.adapterFor(provider.adapterId);
      if (adapter == null) {
        throw const ManagedProviderUsageQueryError(
          ManagedProviderUsageQueryErrorCode.unsupported,
        );
      }
      result = await adapter.fetch(
        provider,
        credentials: _credentials,
        http: _http,
        now: _now(),
      );
      result = result.copyWith(
        providerId: provider.id,
        status: ProviderUsageStatus.ready,
      );
    } on ManagedProviderUsageQueryError catch (error) {
      result = _errorSnapshot(provider.id, previous, error.code);
    } on Object {
      // Do not expose arbitrary exception text. A transport implementation can
      // opt into a more precise typed code via ManagedProviderUsageQueryError.
      result = _errorSnapshot(
        provider.id,
        previous,
        ManagedProviderUsageQueryErrorCode.networkFailed,
      );
    }

    return _commitResult(
      provider: provider,
      generation: generation,
      token: token,
      storageContextGeneration: storageContextGeneration,
      mutationRevision: mutationRevision,
      result: result,
      previous: previous,
    );
  }

  Future<ProviderUsageSnapshot> _commitResult({
    required ManagedProvider provider,
    required int generation,
    required int storageContextGeneration,
    int? token,
    required int mutationRevision,
    required ProviderUsageSnapshot result,
    required ProviderUsageSnapshot? previous,
    bool requiresEnabled = true,
  }) async {
    return _commitGates.putIfAbsent(provider.id, _ProviderCommitGate.new).run(
      () async {
        if (!_isCommitLifecycleCurrent(
          provider: provider,
          generation: generation,
          token: token,
          storageContextGeneration: storageContextGeneration,
          requiresEnabled: requiresEnabled,
        )) {
          _throwInvalidated(provider.id, _invalidationCode(provider.id, token));
        }
        var cacheSaved = false;
        try {
          final committed = await _providerRepository.runIfUnchanged(
            expectedRevision: mutationRevision,
            expectedProvider: provider,
            action: () async {
              cacheSaved = await _usageRepository.saveIf(
                result,
                shouldCommit: () {
                  final stillCurrent = token == null
                      ? _isCurrentConfig(provider, generation, null)
                      : _isCurrent(provider, generation, token);
                  return storageContextGeneration ==
                          _storageContextGeneration &&
                      stillCurrent &&
                      _providerRepository.mutationRevision == mutationRevision;
                },
              );
              if (cacheSaved) _snapshots[provider.id] = result;
            },
          );
          if (!committed || !cacheSaved) {
            await _synchronizeProviders();
            _throwInvalidated(
              provider.id,
              _invalidationCode(provider.id, token),
            );
          }
          return result;
        } on ManagedProviderUsageInvalidated {
          rethrow;
        } on Object {
          if (!_isCommitCurrent(
            provider: provider,
            generation: generation,
            token: token,
            storageContextGeneration: storageContextGeneration,
            mutationRevision: mutationRevision,
            requiresEnabled: requiresEnabled,
          )) {
            try {
              await _synchronizeProviders();
            } on Object {
              // Preserve the typed invalidation outcome if reconciliation
              // itself cannot read the provider catalog.
            }
            _throwInvalidated(
              provider.id,
              _invalidationCode(provider.id, token),
            );
          }
          throw ManagedProviderUsagePersistenceError(
            providerId: provider.id,
            code: ManagedProviderUsagePersistenceErrorCode.saveFailed,
          );
        }
      },
    );
  }

  Future<void> _ensureLoaded() async {
    if (!_loaded) await load();
  }

  void _ensureStorageContextCurrent(
    int expectedGeneration, {
    String providerId = '',
  }) {
    if (_closed || expectedGeneration != _storageContextGeneration) {
      _throwInvalidated(
        providerId,
        ManagedProviderUsageInvalidationCode.refreshCancelled,
      );
    }
  }

  Future<void> _synchronizeProviders() async {
    final configured = await _providerRepository.load();
    final next = <String, ManagedProvider>{
      for (final provider in configured)
        if (provider.id.trim().isNotEmpty) provider.id.trim(): provider,
    };
    final changed =
        next.length != _providers.length ||
        next.entries.any((entry) => _providers[entry.key] != entry.value);
    if (!changed) return;
    _generation++;
    _providers
      ..clear()
      ..addAll(next);
    _snapshots.removeWhere((id, _) => !_providers.containsKey(id));
    for (final provider in _providers.values) {
      if (!provider.enabled) {
        _snapshots[provider.id] = _unsupportedSnapshot(
          provider.id,
          _snapshots[provider.id],
        );
      }
    }
  }

  bool _isCurrent(ManagedProvider provider, int generation, int token) =>
      _isCurrentConfig(provider, generation, token) && provider.enabled;

  bool _isCurrentConfig(ManagedProvider provider, int generation, int? token) =>
      generation == _generation &&
      (token == null || token == _tokens[provider.id]) &&
      identical(_providers[provider.id], provider);

  bool _isCommitCurrent({
    required ManagedProvider provider,
    required int generation,
    required int storageContextGeneration,
    required int? token,
    required int mutationRevision,
    required bool requiresEnabled,
  }) =>
      _isCommitLifecycleCurrent(
        provider: provider,
        generation: generation,
        storageContextGeneration: storageContextGeneration,
        token: token,
        requiresEnabled: requiresEnabled,
      ) &&
      _providerRepository.mutationRevision == mutationRevision;

  bool _isCommitLifecycleCurrent({
    required ManagedProvider provider,
    required int generation,
    required int storageContextGeneration,
    required int? token,
    required bool requiresEnabled,
  }) {
    final current = token == null
        ? _isCurrentConfig(provider, generation, null)
        : _isCurrent(provider, generation, token);
    return !_closed &&
        storageContextGeneration == _storageContextGeneration &&
        current &&
        (!requiresEnabled || provider.enabled);
  }

  ManagedProviderUsageInvalidationCode _invalidationCode(
    String providerId,
    int? token,
  ) {
    if (token != null && token != _tokens[providerId]) {
      return ManagedProviderUsageInvalidationCode.refreshCancelled;
    }
    if (!_providers.containsKey(providerId)) {
      return ManagedProviderUsageInvalidationCode.providerDeleted;
    }
    return ManagedProviderUsageInvalidationCode.providerChanged;
  }

  Never _throwInvalidated(
    String providerId,
    ManagedProviderUsageInvalidationCode code,
  ) =>
      throw ManagedProviderUsageInvalidated(providerId: providerId, code: code);

  static ProviderUsageSnapshot _unsupportedSnapshot(
    String providerId,
    ProviderUsageSnapshot? previous,
  ) =>
      (previous ??
              ProviderUsageSnapshot(
                providerId: providerId,
                status: ProviderUsageStatus.unsupported,
              ))
          .copyWith(
            providerId: providerId,
            status: ProviderUsageStatus.unsupported,
            lastErrorCode: ManagedProviderUsageQueryErrorCode.unsupported.name,
            lastErrorMessage: const ManagedProviderUsageQueryError(
              ManagedProviderUsageQueryErrorCode.unsupported,
            ).message,
          );

  static ProviderUsageSnapshot _errorSnapshot(
    String providerId,
    ProviderUsageSnapshot? previous,
    ManagedProviderUsageQueryErrorCode code,
  ) =>
      (previous ??
              ProviderUsageSnapshot(
                providerId: providerId,
                status: ProviderUsageStatus.error,
              ))
          .copyWith(
            providerId: providerId,
            status: ProviderUsageStatus.error,
            lastErrorCode: code.name,
            lastErrorMessage: ManagedProviderUsageQueryError(code).message,
          );
}

class _PendingRefresh {
  _PendingRefresh({
    required this.provider,
    required this.generation,
    required this.token,
    required this.future,
  });

  final ManagedProvider provider;
  final int generation;
  final int token;
  final Future<ProviderUsageSnapshot> future;
  bool cancelled = false;
}

class _ProviderCommitGate {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) async {
    final previous = _tail;
    final release = Completer<void>();
    final queued = previous.then((_) => release.future);
    _tail = queued;
    await previous;
    try {
      return await action();
    } finally {
      if (!release.isCompleted) release.complete();
      if (identical(_tail, queued)) _tail = Future<void>.value();
    }
  }
}
