import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/managed_provider.dart';
import '../models/provider_usage_snapshot.dart';
import '../services/provider_usage/managed_provider_usage_coordinator.dart'
    as coordinator;

enum ManagedProviderUsageLoadStatus { initial, loading, ready, error }

enum ManagedProviderUsageErrorCode {
  loadFailed,
  refreshFailed,
  persistenceFailed,
  invalidated,
}

class ManagedProviderUsageState extends Equatable {
  ManagedProviderUsageState({
    this.status = ManagedProviderUsageLoadStatus.initial,
    Map<String, ProviderUsageSnapshot> snapshots = const {},
    Iterable<String> refreshingProviderIds = const {},
    Map<String, int> refreshOperationCounts = const {},
    this.isRefreshing = false,
    this.generation = 0,
    this.errorCode,
    this.errorMessage,
  }) : snapshots = Map.unmodifiable(snapshots),
       refreshingProviderIds = Set.unmodifiable(refreshingProviderIds),
       refreshOperationCounts = Map.unmodifiable(refreshOperationCounts);

  final ManagedProviderUsageLoadStatus status;
  final Map<String, ProviderUsageSnapshot> snapshots;
  final Set<String> refreshingProviderIds;
  final Map<String, int> refreshOperationCounts;
  final bool isRefreshing;
  final int generation;
  final ManagedProviderUsageErrorCode? errorCode;
  final String? errorMessage;

  ProviderUsageSnapshot? snapshotFor(String providerId) =>
      snapshots[providerId.trim()];

  ProviderUsageStatus? statusFor(String providerId) =>
      snapshotFor(providerId)?.status;

  bool isRefreshingProvider(String providerId) =>
      refreshingProviderIds.contains(providerId.trim());

  int refreshOperationCountFor(String providerId) =>
      refreshOperationCounts[providerId.trim()] ?? 0;

  ManagedProviderUsageState copyWith({
    ManagedProviderUsageLoadStatus? status,
    Map<String, ProviderUsageSnapshot>? snapshots,
    Iterable<String>? refreshingProviderIds,
    Map<String, int>? refreshOperationCounts,
    bool? isRefreshing,
    int? generation,
    ManagedProviderUsageErrorCode? errorCode,
    String? errorMessage,
    bool clearError = false,
  }) => ManagedProviderUsageState(
    status: status ?? this.status,
    snapshots: snapshots ?? this.snapshots,
    refreshingProviderIds: refreshingProviderIds ?? this.refreshingProviderIds,
    refreshOperationCounts:
        refreshOperationCounts ?? this.refreshOperationCounts,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    generation: generation ?? this.generation,
    errorCode: clearError ? null : errorCode ?? this.errorCode,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );

  @override
  List<Object?> get props => [
    status,
    snapshots,
    refreshingProviderIds,
    refreshOperationCounts,
    isRefreshing,
    generation,
    errorCode,
    errorMessage,
  ];
}

/// App-shell-scoped usage state. It consumes the coordinator only; network
/// construction and response normalization stay below this boundary.
class ManagedProviderUsageCubit extends Cubit<ManagedProviderUsageState> {
  ManagedProviderUsageCubit({
    required coordinator.ManagedProviderUsageCoordinator coordinator,
    DateTime Function()? now,
  }) : _coordinator = coordinator,
       _now = now ?? DateTime.now,
       super(ManagedProviderUsageState());

  final coordinator.ManagedProviderUsageCoordinator _coordinator;
  final DateTime Function() _now;
  Future<void>? _loadFlight;
  final Map<String, _EnsureFlight> _ensureFlights = {};
  final Map<String, int> _ensureGenerations = {};
  final Map<String, Set<int>> _refreshOperations = {};
  int _nextRefreshToken = 0;

  Future<void> load() {
    if (isClosed) return Future<void>.value();
    final existing = _loadFlight;
    if (existing != null) return existing;
    final future = _loadInternal();
    _loadFlight = future;
    return future.whenComplete(() {
      if (identical(_loadFlight, future)) _loadFlight = null;
    });
  }

  Future<void> reload() => load();

  Future<void> _loadInternal() async {
    if (!isClosed) {
      emit(
        state.copyWith(
          status: ManagedProviderUsageLoadStatus.loading,
          clearError: true,
        ),
      );
    }
    try {
      final loaded = await _coordinator.load();
      if (isClosed) return;
      _emitCoordinatorState(
        loaded,
        status: ManagedProviderUsageLoadStatus.ready,
        clearError: true,
      );
    } on Object {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: ManagedProviderUsageLoadStatus.error,
          errorCode: ManagedProviderUsageErrorCode.loadFailed,
          errorMessage: null,
        ),
      );
    }
  }

  Future<ProviderUsageSnapshot?> refreshOne(String providerId) async {
    await load();
    final id = providerId.trim();
    if (isClosed) return state.snapshotFor(id);
    if (id.isEmpty || !_coordinator.providers.any((p) => p.id == id)) {
      return state.snapshotFor(id);
    }
    final refreshToken = _beginRefresh({id})[id]!;
    try {
      final result = await _coordinator.refreshOne(id);
      if (isClosed) return result;
      _emitCoordinatorState(
        _coordinator.state,
        status: ManagedProviderUsageLoadStatus.ready,
        clearError: true,
      );
      return result;
    } on coordinator.ManagedProviderUsageInvalidated catch (error) {
      await _handleInvalidation(error);
      return null;
    } on coordinator.ManagedProviderUsagePersistenceError {
      _setOperationError(ManagedProviderUsageErrorCode.persistenceFailed);
      return state.snapshotFor(id);
    } on Object {
      _setOperationError(ManagedProviderUsageErrorCode.refreshFailed);
      return state.snapshotFor(id);
    } finally {
      _endRefresh(id, refreshToken);
    }
  }

  /// Runs an editor validation query without persisting its result.
  Future<ProviderUsageSnapshot?> queryOne(String providerId) async {
    await load();
    final id = providerId.trim();
    if (isClosed || id.isEmpty) return state.snapshotFor(id);
    try {
      final result = await _coordinator.queryOne(id);
      if (isClosed) return result;
      final snapshots = Map<String, ProviderUsageSnapshot>.from(state.snapshots)
        ..[id] = result;
      emit(
        state.copyWith(
          status: ManagedProviderUsageLoadStatus.ready,
          snapshots: snapshots,
          clearError: true,
        ),
      );
      return result;
    } on Object {
      _setOperationError(ManagedProviderUsageErrorCode.refreshFailed);
      return state.snapshotFor(id);
    }
  }

  Future<ProviderUsageSnapshot?> queryProvider(ManagedProvider provider) async {
    await load();
    if (isClosed) return state.snapshotFor(provider.id);
    try {
      final result = await _coordinator.queryProvider(provider);
      if (isClosed) return result;
      final snapshots = Map<String, ProviderUsageSnapshot>.from(state.snapshots)
        ..[provider.id] = result;
      emit(
        state.copyWith(
          status: ManagedProviderUsageLoadStatus.ready,
          snapshots: snapshots,
          clearError: true,
        ),
      );
      return result;
    } on Object {
      _setOperationError(ManagedProviderUsageErrorCode.refreshFailed);
      return state.snapshotFor(provider.id);
    }
  }

  Future<List<ProviderUsageSnapshot>> refreshAll() async {
    await load();
    if (isClosed) return const [];
    final ids = _coordinator.providers
        .where((provider) => provider.enabled)
        .map((provider) => provider.id)
        .toSet();
    final refreshTokens = _beginRefresh(ids);
    try {
      final results = await _coordinator.refreshAll();
      if (!isClosed) {
        _emitCoordinatorState(
          _coordinator.state,
          status: ManagedProviderUsageLoadStatus.ready,
          clearError: true,
        );
      }
      return results;
    } on coordinator.ManagedProviderUsageInvalidated catch (error) {
      await _handleInvalidation(error);
      return const [];
    } on coordinator.ManagedProviderUsagePersistenceError {
      _setOperationError(ManagedProviderUsageErrorCode.persistenceFailed);
      return const [];
    } on Object {
      _setOperationError(ManagedProviderUsageErrorCode.refreshFailed);
      return const [];
    } finally {
      _endRefreshes(refreshTokens);
    }
  }

  Future<void> cancelForProvider(String providerId) async {
    if (isClosed) return;
    final id = providerId.trim();
    if (id.isEmpty) return;
    _invalidateEnsureFlight(id);
    try {
      await _coordinator.cancelForProvider(id);
    } on Object {
      _setOperationError(ManagedProviderUsageErrorCode.refreshFailed);
      return;
    }
  }

  /// Invalidates all in-flight work before the AppStorage home context is
  /// rebound. This clears Cubit-level ensure flights as well as the
  /// coordinator's transport/commit generation.
  Future<void> invalidateForStorageContextChange() async {
    if (isClosed) return;
    for (final id in _ensureFlights.keys.toList(growable: false)) {
      _invalidateEnsureFlight(id);
    }
    _refreshOperations.clear();
    _emitRefreshState(clearError: true);
    await _coordinator.invalidateForStorageContextChange();
  }

  /// Refreshes only an absent or expired snapshot. Calls for one Provider are
  /// coalesced even before they reach the coordinator.
  Future<ProviderUsageSnapshot?> ensureFresh(String providerId) async {
    await load();
    final id = providerId.trim();
    if (isClosed) return state.snapshotFor(id);
    final generation = _ensureGenerations[id] ?? 0;
    final existing = _ensureFlights[id];
    if (existing != null && existing.generation == generation) {
      return existing.future;
    }
    if (existing != null) _ensureFlights.remove(id);

    ManagedProvider? provider;
    for (final candidate in _coordinator.providers) {
      if (candidate.id == id) {
        provider = candidate;
        break;
      }
    }
    if (provider == null || !provider.enabled) return state.snapshotFor(id);
    final snapshot = state.snapshotFor(id);
    if (_isFresh(snapshot)) return snapshot;

    final flight = refreshOne(id);
    final record = _EnsureFlight(future: flight, generation: generation);
    _ensureFlights[id] = record;
    return flight.whenComplete(() {
      if (identical(_ensureFlights[id], record) &&
          _ensureGenerations[id] == generation) {
        _ensureFlights.remove(id);
      }
    });
  }

  Future<void> removeProvider(String providerId) =>
      removeProviders([providerId]);

  /// Rehydrates the coordinator after the repository's deletion cleanup has
  /// completed, ensuring removed Providers cannot remain in memory.
  Future<void> removeProviders(Iterable<String> providerIds) async {
    if (isClosed) return;
    final ids = providerIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return;
    for (final id in ids) {
      _invalidateEnsureFlight(id);
    }
    _refreshOperations.removeWhere((id, _) => ids.contains(id));
    final snapshots = Map<String, ProviderUsageSnapshot>.from(state.snapshots)
      ..removeWhere((id, _) => ids.contains(id));
    final refreshing = Set<String>.from(state.refreshingProviderIds)
      ..removeWhere(ids.contains);
    if (!isClosed) {
      emit(
        state.copyWith(
          snapshots: snapshots,
          refreshingProviderIds: refreshing,
          refreshOperationCounts: _refreshOperationCounts(),
          isRefreshing: refreshing.isNotEmpty,
          clearError: true,
        ),
      );
    }
    try {
      await Future.wait([
        for (final id in ids) _coordinator.cancelForProvider(id),
      ]);
      final loaded = await _coordinator.load();
      if (!isClosed) _emitCoordinatorState(loaded, clearError: true);
    } on Object {
      if (!isClosed) {
        emit(
          state.copyWith(
            status: ManagedProviderUsageLoadStatus.error,
            errorCode: ManagedProviderUsageErrorCode.loadFailed,
            errorMessage: null,
          ),
        );
      }
    }
  }

  bool _isFresh(ProviderUsageSnapshot? snapshot) {
    if (snapshot == null || snapshot.status != ProviderUsageStatus.ready) {
      return false;
    }
    final staleAt = snapshot.staleAt;
    return staleAt == null || _now().millisecondsSinceEpoch < staleAt;
  }

  Map<String, int> _beginRefresh(Iterable<String> ids) {
    if (isClosed) return const {};
    final operationTokens = <String, int>{};
    for (final id in ids) {
      final token = ++_nextRefreshToken;
      (_refreshOperations[id] ??= <int>{}).add(token);
      operationTokens[id] = token;
    }
    _emitRefreshState(clearError: true);
    return operationTokens;
  }

  void _endRefresh(String id, int token) {
    final operations = _refreshOperations[id];
    operations?.remove(token);
    if (operations != null && operations.isEmpty) {
      _refreshOperations.remove(id);
    }
    _emitRefreshState();
  }

  void _endRefreshes(Map<String, int> operationTokens) {
    for (final entry in operationTokens.entries) {
      final operations = _refreshOperations[entry.key];
      operations?.remove(entry.value);
      if (operations != null && operations.isEmpty) {
        _refreshOperations.remove(entry.key);
      }
    }
    _emitRefreshState();
  }

  void _emitRefreshState({bool clearError = false}) {
    if (isClosed) return;
    final refreshing = _refreshOperations.keys.toSet();
    emit(
      state.copyWith(
        refreshingProviderIds: refreshing,
        refreshOperationCounts: _refreshOperationCounts(),
        isRefreshing: refreshing.isNotEmpty,
        clearError: clearError,
      ),
    );
  }

  Map<String, int> _refreshOperationCounts() => {
    for (final entry in _refreshOperations.entries)
      if (entry.value.isNotEmpty) entry.key: entry.value.length,
  };

  void _invalidateEnsureFlight(String id) {
    _ensureGenerations[id] = (_ensureGenerations[id] ?? 0) + 1;
    _ensureFlights.remove(id);
  }

  void _emitCoordinatorState(
    coordinator.ManagedProviderUsageState source, {
    ManagedProviderUsageLoadStatus? status,
    bool clearError = false,
  }) {
    if (isClosed) return;
    emit(
      state.copyWith(
        status: status ?? ManagedProviderUsageLoadStatus.ready,
        snapshots: source.snapshots,
        generation: source.generation,
        clearError: clearError,
      ),
    );
  }

  Future<void> _handleInvalidation(
    coordinator.ManagedProviderUsageInvalidated error,
  ) async {
    if (error.code ==
        coordinator.ManagedProviderUsageInvalidationCode.refreshCancelled) {
      // Cancellation does not change the Provider catalog. Reloading the
      // coordinator here could advance its generation and invalidate a
      // successor refresh started immediately after the cancellation.
      return;
    }
    try {
      final loaded = await _coordinator.load();
      if (isClosed) return;
      _emitCoordinatorState(
        loaded,
        status: ManagedProviderUsageLoadStatus.ready,
        clearError:
            error.code ==
            coordinator.ManagedProviderUsageInvalidationCode.providerDeleted,
      );
    } on Object {
      if (!isClosed) {
        emit(
          state.copyWith(
            status: ManagedProviderUsageLoadStatus.error,
            errorCode: ManagedProviderUsageErrorCode.invalidated,
            errorMessage: null,
          ),
        );
      }
    }
  }

  void _setOperationError(ManagedProviderUsageErrorCode code) {
    if (isClosed) return;
    emit(
      state.copyWith(
        status: ManagedProviderUsageLoadStatus.error,
        errorCode: code,
        errorMessage: null,
      ),
    );
  }

  /// Closing is non-blocking: in-flight coordinator work may finish, but all
  /// completion paths guard [isClosed] and never emit or surface a late error.
  @override
  Future<void> close() {
    _ensureFlights.clear();
    _ensureGenerations.clear();
    _refreshOperations.clear();
    return super.close();
  }
}

class _EnsureFlight {
  const _EnsureFlight({required this.future, required this.generation});

  final Future<ProviderUsageSnapshot?> future;
  final int generation;
}
