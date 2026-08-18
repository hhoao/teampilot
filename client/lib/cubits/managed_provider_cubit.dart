import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/managed_provider.dart';
import '../repositories/managed_provider_repository.dart';

enum ManagedProviderLoadStatus { initial, loading, ready, error }

enum ManagedProviderErrorCode { loadFailed, saveFailed, deleteFailed }

class ManagedProviderState extends Equatable {
  ManagedProviderState({
    this.status = ManagedProviderLoadStatus.initial,
    Iterable<ManagedProvider> providers = const [],
    this.errorCode,
    this.errorMessage,
  }) : providers = List.unmodifiable(providers);

  final ManagedProviderLoadStatus status;
  final List<ManagedProvider> providers;
  final ManagedProviderErrorCode? errorCode;
  final String? errorMessage;

  bool get isLoaded => status == ManagedProviderLoadStatus.ready;

  ManagedProvider? providerFor(String id) {
    final normalized = id.trim();
    for (final provider in providers) {
      if (provider.id == normalized) return provider;
    }
    return null;
  }

  List<ManagedProvider> get enabledProviders =>
      List.unmodifiable(providers.where((provider) => provider.enabled));

  ManagedProviderState copyWith({
    ManagedProviderLoadStatus? status,
    Iterable<ManagedProvider>? providers,
    ManagedProviderErrorCode? errorCode,
    String? errorMessage,
    bool clearError = false,
  }) => ManagedProviderState(
    status: status ?? this.status,
    providers: providers ?? this.providers,
    errorCode: clearError ? null : errorCode ?? this.errorCode,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );

  @override
  List<Object?> get props => [status, providers, errorCode, errorMessage];
}

/// App-shell-scoped state owner for the CLI-independent Provider catalog.
class ManagedProviderCubit extends Cubit<ManagedProviderState> {
  ManagedProviderCubit({
    required ManagedProviderRepository repository,
    Future<void> Function(String providerId)? onProviderDeletedState,
  }) : _repository = repository,
       _onProviderDeletedState = onProviderDeletedState,
       super(ManagedProviderState());

  final ManagedProviderRepository _repository;
  final Future<void> Function(String providerId)? _onProviderDeletedState;
  Future<void>? _loadFlight;
  Future<void> _mutationTail = Future<void>.value();
  int _catalogRevision = 0;

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
    final revision = _catalogRevision;
    await _mutationTail;
    if (isClosed) return;
    emit(
      state.copyWith(
        status: ManagedProviderLoadStatus.loading,
        clearError: true,
      ),
    );
    try {
      final providers = await _repository.load();
      if (isClosed || revision != _catalogRevision) return;
      emit(
        state.copyWith(
          status: ManagedProviderLoadStatus.ready,
          providers: providers,
          clearError: true,
        ),
      );
    } on Object {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: ManagedProviderLoadStatus.error,
          errorCode: ManagedProviderErrorCode.loadFailed,
          errorMessage: 'Unable to load managed providers.',
        ),
      );
    }
  }

  Future<void> add(ManagedProvider provider) => upsert(provider);

  Future<void> upsert(ManagedProvider provider) async {
    if (isClosed) return;
    if (provider.id.trim().isEmpty) {
      if (!isClosed) {
        emit(
          state.copyWith(
            status: ManagedProviderLoadStatus.error,
            errorCode: ManagedProviderErrorCode.saveFailed,
            errorMessage: 'Unable to save managed provider.',
          ),
        );
      }
      return;
    }
    final normalized = provider.copyWith(id: provider.id.trim());
    await _serializeMutation(() async {
      await _repository.upsert(normalized);
      _replace(normalized);
    }, errorCode: ManagedProviderErrorCode.saveFailed);
  }

  Future<void> update(ManagedProvider provider) => upsert(provider);

  Future<void> enable(String providerId) => _setEnabled(providerId, true);

  Future<void> disable(String providerId) => _setEnabled(providerId, false);

  Future<void> _setEnabled(String providerId, bool enabled) async {
    if (isClosed) return;
    final id = providerId.trim();
    if (id.isEmpty) return;
    await _serializeMutation(() async {
      final provider = state.providerFor(id);
      if (provider == null || provider.enabled == enabled) return;
      final next = provider.copyWith(enabled: enabled);
      await _repository.upsert(next);
      _replace(next);
    }, errorCode: ManagedProviderErrorCode.saveFailed);
  }

  Future<void> delete(String providerId) async {
    if (isClosed) return;
    final id = providerId.trim();
    if (id.isEmpty) return;
    await _serializeMutation(() async {
      await _repository.delete(id);
      final onProviderDeletedState = _onProviderDeletedState;
      if (onProviderDeletedState != null) {
        await onProviderDeletedState(id);
      }
      if (isClosed) return;
      emit(
        state.copyWith(
          status: ManagedProviderLoadStatus.ready,
          providers: state.providers.where((provider) => provider.id != id),
          clearError: true,
        ),
      );
    }, errorCode: ManagedProviderErrorCode.deleteFailed);
  }

  Future<void> _serializeMutation(
    Future<void> Function() action, {
    required ManagedProviderErrorCode errorCode,
  }) async {
    _catalogRevision++;
    final previous = _mutationTail;
    final release = Completer<void>();
    final queued = previous.then((_) => release.future);
    _mutationTail = queued;
    await previous;
    try {
      if (!isClosed) emit(state.copyWith(clearError: true));
      await action();
    } on Object {
      if (!isClosed) {
        emit(
          state.copyWith(
            status: ManagedProviderLoadStatus.error,
            errorCode: errorCode,
            errorMessage: _messageFor(errorCode),
          ),
        );
      }
    } finally {
      if (!release.isCompleted) release.complete();
      if (identical(_mutationTail, queued)) {
        _mutationTail = Future<void>.value();
      }
    }
  }

  void _replace(ManagedProvider provider) {
    if (isClosed) return;
    final next = [
      for (final current in state.providers)
        if (current.id != provider.id) current,
      provider,
    ];
    emit(
      state.copyWith(
        status: ManagedProviderLoadStatus.ready,
        providers: next,
        clearError: true,
      ),
    );
  }

  static String _messageFor(ManagedProviderErrorCode code) => switch (code) {
    ManagedProviderErrorCode.loadFailed => 'Unable to load managed providers.',
    ManagedProviderErrorCode.saveFailed => 'Unable to save managed provider.',
    ManagedProviderErrorCode.deleteFailed =>
      'Unable to delete managed provider.',
  };
}
