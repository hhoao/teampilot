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
    this.isRefreshing = false,
    this.generation = 0,
    this.errorCode,
    this.errorMessage,
  }) : snapshots = Map.unmodifiable(snapshots),
       refreshingProviderIds = Set.unmodifiable(refreshingProviderIds);

  final ManagedProviderUsageLoadStatus status;
  final Map<String, ProviderUsageSnapshot> snapshots;
  final Set<String> refreshingProviderIds;
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

  ManagedProviderUsageState copyWith({
    ManagedProviderUsageLoadStatus? status,
    Map<String, ProviderUsageSnapshot>? snapshots,
    Iterable<String>? refreshingProviderIds,
    bool? isRefreshing,
    int? generation,
    ManagedProviderUsageErrorCode? errorCode,
    String? errorMessage,
    bool clearError = false,
  }) => ManagedProviderUsageState(
    status: status ?? this.status,
    snapshots: snapshots ?? this.snapshots,
    refreshingProviderIds: refreshingProviderIds ?? this.refreshingProviderIds,
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
  final Map<String, Future<ProviderUsageSnapshot?>> _ensureFlights = {};

  Future<void> load() {
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
          errorMessage: 'Unable to load managed provider usage.',
        ),
      );
    }
  }

  Future<ProviderUsageSnapshot?> refreshOne(String providerId) async {
    await load();
    final id = providerId.trim();
    if (id.isEmpty || !_coordinator.providers.any((p) => p.id == id)) {
      return state.snapshotFor(id);
    }
    _beginRefresh({id});
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
      _endRefresh(id);
    }
  }

  Future<List<ProviderUsageSnapshot>> refreshAll() async {
    await load();
    final ids = _coordinator.providers
        .where((provider) => provider.enabled)
        .map((provider) => provider.id)
        .toSet();
    _beginRefresh(ids);
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
      _endRefreshes(ids);
    }
  }

  Future<void> cancelForProvider(String providerId) async {
    final id = providerId.trim();
    if (id.isEmpty) return;
    try {
      await _coordinator.cancelForProvider(id);
    } on Object {
      _setOperationError(ManagedProviderUsageErrorCode.refreshFailed);
      return;
    }
    _endRefresh(id);
  }

  /// Refreshes only an absent or expired snapshot. Calls for one Provider are
  /// coalesced even before they reach the coordinator.
  Future<ProviderUsageSnapshot?> ensureFresh(String providerId) async {
    await load();
    final id = providerId.trim();
    final existing = _ensureFlights[id];
    if (existing != null) return existing;

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
    _ensureFlights[id] = flight;
    return flight.whenComplete(() {
      if (identical(_ensureFlights[id], flight)) _ensureFlights.remove(id);
    });
  }

  Future<void> removeProvider(String providerId) =>
      removeProviders([providerId]);

  /// Rehydrates the coordinator after the repository's deletion cleanup has
  /// completed, ensuring removed Providers cannot remain in memory.
  Future<void> removeProviders(Iterable<String> providerIds) async {
    final ids = providerIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return;
    final snapshots = Map<String, ProviderUsageSnapshot>.from(state.snapshots)
      ..removeWhere((id, _) => ids.contains(id));
    final refreshing = Set<String>.from(state.refreshingProviderIds)
      ..removeWhere(ids.contains);
    if (!isClosed) {
      emit(
        state.copyWith(
          snapshots: snapshots,
          refreshingProviderIds: refreshing,
          isRefreshing: refreshing.isNotEmpty,
          clearError: true,
        ),
      );
    }
    try {
      final loaded = await _coordinator.load();
      if (!isClosed) _emitCoordinatorState(loaded, clearError: true);
    } on Object {
      if (!isClosed) {
        emit(
          state.copyWith(
            status: ManagedProviderUsageLoadStatus.error,
            errorCode: ManagedProviderUsageErrorCode.loadFailed,
            errorMessage: 'Unable to reload managed provider usage.',
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

  void _beginRefresh(Iterable<String> ids) {
    if (isClosed) return;
    final refreshing = {...state.refreshingProviderIds, ...ids};
    emit(
      state.copyWith(
        refreshingProviderIds: refreshing,
        isRefreshing: refreshing.isNotEmpty,
        clearError: true,
      ),
    );
  }

  void _endRefresh(String id) => _endRefreshes([id]);

  void _endRefreshes(Iterable<String> ids) {
    if (isClosed) return;
    final refreshing = Set<String>.from(state.refreshingProviderIds)
      ..removeAll(ids);
    emit(
      state.copyWith(
        refreshingProviderIds: refreshing,
        isRefreshing: refreshing.isNotEmpty,
      ),
    );
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
            errorMessage: 'Managed provider usage was invalidated.',
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
        errorMessage: _messageFor(code),
      ),
    );
  }

  static String _messageFor(ManagedProviderUsageErrorCode code) =>
      switch (code) {
        ManagedProviderUsageErrorCode.loadFailed =>
          'Unable to load managed provider usage.',
        ManagedProviderUsageErrorCode.refreshFailed =>
          'Unable to refresh managed provider usage.',
        ManagedProviderUsageErrorCode.persistenceFailed =>
          'Unable to save managed provider usage.',
        ManagedProviderUsageErrorCode.invalidated =>
          'Managed provider usage was invalidated.',
      };
}
