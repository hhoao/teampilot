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
  final Map<String, _ProviderCommitGate> _commitGates = {};
  final Map<String, int> _tokens = {};
  int _generation = 0;
  bool _loaded = false;
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
    final existing = _loadFlight;
    if (existing != null) return existing;
    final flight = _loadCacheAndProviders();
    _loadFlight = flight;
    return flight.whenComplete(() {
      if (identical(_loadFlight, flight)) _loadFlight = null;
    });
  }

  Future<ManagedProviderUsageState> _loadCacheAndProviders() async {
    final cached = await _usageRepository.load();
    final configured = await _providerRepository.load();
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
    await _ensureLoaded();
    await _synchronizeProviders();
    final id = providerId.trim();
    final provider = _providers[id];
    if (provider == null) return _unsupportedSnapshot(id, _snapshots[id]);
    return _refreshLoadedProvider(provider, _generation);
  }

  /// Refreshes all configured providers through the same per-provider single-
  /// flight map used by targeted refreshes.
  Future<List<ProviderUsageSnapshot>> refreshAll() {
    final existing = _refreshAllFlight;
    if (existing != null) return existing;
    final flight = _refreshAllInternal();
    _refreshAllFlight = flight;
    return flight.whenComplete(() {
      if (identical(_refreshAllFlight, flight)) _refreshAllFlight = null;
    });
  }

  Future<List<ProviderUsageSnapshot>> _refreshAllInternal() async {
    await _ensureLoaded();
    await _synchronizeProviders();
    // Do not advance the generation merely because the caller chose the
    // aggregate entry point. The per-provider pending future is shared with
    // targeted refreshes, so this must not create a duplicate request.
    final generation = _generation;
    final current = _providers.values.toList(growable: false);
    final results = await Future.wait(
      current.map((provider) => _refreshForAll(provider, generation)),
    );
    return [
      for (final result in results)
        if (result != null) result,
    ];
  }

  Future<ProviderUsageSnapshot?> _refreshForAll(
    ManagedProvider provider,
    int generation,
  ) async {
    try {
      return await _refreshLoadedProvider(provider, generation);
    } on ManagedProviderUsageInvalidated {
      final current = _providers[provider.id];
      if (current == null) return null;
      if (!current.enabled) {
        return _completeDisabledProvider(
          current,
          generation: _generation,
          mutationRevision: _providerRepository.mutationRevision,
        );
      }
      // A cancellation or configuration change during all-refresh is retried
      // through the same serialized pending map, never concurrently.
      return _refreshLoadedProvider(current, _generation);
    }
  }

  /// Invalidates an in-flight provider request. Dart HTTP transports may not
  /// be cancellable, so the generation/token check discards its result.
  Future<void> cancelForProvider(String providerId) async {
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

  Future<ProviderUsageSnapshot> _refreshLoadedProvider(
    ManagedProvider provider,
    int generation,
  ) {
    final id = provider.id;
    if (!provider.enabled) {
      return _completeDisabledProvider(
        provider,
        generation: generation,
        mutationRevision: _providerRepository.mutationRevision,
      );
    }
    final previousPending = _pending[id];
    if (previousPending != null) {
      if (previousPending.cancelled) {
        return previousPending.future.then(
          (_) => _startSuccessorAfterPending(id),
          onError: (Object _, StackTrace __) => _startSuccessorAfterPending(id),
        );
      }
      if (previousPending.provider == provider) {
        return previousPending.future;
      }
      // Configuration changed while the old request was in flight. The
      // transport may not be cancellable, so wait for it before starting the
      // replacement; this preserves one underlying request per provider.
      return previousPending.future.then(
        (_) => _startSuccessorAfterPending(id),
        onError: (Object _, StackTrace __) => _startSuccessorAfterPending(id),
      );
    }

    final token = (_tokens[id] ?? 0) + 1;
    _tokens[id] = token;
    final future = _executeRefresh(
      provider,
      generation,
      token,
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

  Future<ProviderUsageSnapshot> _startSuccessorAfterPending(String id) async {
    await _synchronizeProviders();
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
        mutationRevision: _providerRepository.mutationRevision,
      );
    }
    return _refreshLoadedProvider(current, _generation);
  }

  Future<ProviderUsageSnapshot> _completeDisabledProvider(
    ManagedProvider provider, {
    required int generation,
    required int mutationRevision,
  }) async {
    final result = _unsupportedSnapshot(provider.id, _snapshots[provider.id]);
    return _commitResult(
      provider: provider,
      generation: generation,
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
    int mutationRevision,
  ) async {
    final previous = _snapshots[provider.id];
    if (!provider.enabled) {
      final result = _unsupportedSnapshot(provider.id, previous);
      return _commitResult(
        provider: provider,
        generation: generation,
        token: token,
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
      mutationRevision: mutationRevision,
      result: result,
      previous: previous,
    );
  }

  Future<ProviderUsageSnapshot> _commitResult({
    required ManagedProvider provider,
    required int generation,
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
                  return stillCurrent &&
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
    required int? token,
    required int mutationRevision,
    required bool requiresEnabled,
  }) =>
      _isCommitLifecycleCurrent(
        provider: provider,
        generation: generation,
        token: token,
        requiresEnabled: requiresEnabled,
      ) &&
      _providerRepository.mutationRevision == mutationRevision;

  bool _isCommitLifecycleCurrent({
    required ManagedProvider provider,
    required int generation,
    required int? token,
    required bool requiresEnabled,
  }) {
    final current = token == null
        ? _isCurrentConfig(provider, generation, null)
        : _isCurrent(provider, generation, token);
    return current && (!requiresEnabled || provider.enabled);
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
