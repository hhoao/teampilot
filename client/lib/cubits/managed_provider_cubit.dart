import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/managed_provider.dart';
import '../repositories/managed_provider_repository.dart';
import '../services/provider_usage/managed_provider_cli_binding.dart';
import '../services/provider_usage/managed_provider_cli_row_janitor.dart';
import 'app_provider_cubit.dart';

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
    Future<void> Function(ManagedProvider provider)?
    onProviderDeletedCredentialCleanup,
    AppProviderCubit? appProviderCubit,
    ManagedProviderCliBinding binding = const ManagedProviderCliBinding(),
    ManagedProviderCliRowJanitor? rowJanitor,
  }) : _repository = repository,
       _onProviderDeletedState = onProviderDeletedState,
       _onProviderDeletedCredentialCleanup = onProviderDeletedCredentialCleanup,
       _appProviderCubit = appProviderCubit,
       _binding = binding,
       _rowJanitor = rowJanitor,
       super(ManagedProviderState());

  final ManagedProviderRepository _repository;
  final Future<void> Function(String providerId)? _onProviderDeletedState;
  final Future<void> Function(ManagedProvider provider)?
  _onProviderDeletedCredentialCleanup;
  final AppProviderCubit? _appProviderCubit;
  final ManagedProviderCliBinding _binding;
  final ManagedProviderCliRowJanitor? _rowJanitor;
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
      if (isClosed || revision != _catalogRevision) return;
      emit(
        state.copyWith(
          status: ManagedProviderLoadStatus.error,
          errorCode: ManagedProviderErrorCode.loadFailed,
          errorMessage: null,
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
            errorMessage: null,
          ),
        );
      }
      return;
    }
    final trimmed = provider.copyWith(id: provider.id.trim());
    final normalized = await _bindIntentSource(trimmed);
    await _serializeMutation(() async {
      await _repository.upsert(normalized);
      _replace(normalized);
    }, errorCode: ManagedProviderErrorCode.saveFailed);
  }

  /// Expands a preset intent source (`cli:cursor`) to the per-entry source
  /// and ensures the dedicated CLI provider row exists. Legacy and already
  /// per-entry sources pass through unchanged.
  Future<ManagedProvider> _bindIntentSource(ManagedProvider provider) async {
    final source = provider.endpointConfig.credentialSource.trim();
    final next = _binding.resolveIntentSource(
      source: source,
      managedProviderId: provider.id,
    );
    if (next == null) {
      await _ensureCliRow(provider);
      return provider;
    }
    final bound = provider.copyWith(
      endpointConfig: _withCredentialSource(provider.endpointConfig, next),
    );
    await _ensureCliRow(bound);
    return bound;
  }

  static ManagedProviderEndpointConfig _withCredentialSource(
    ManagedProviderEndpointConfig config,
    String credentialSource,
  ) => ManagedProviderEndpointConfig(
    url: config.url,
    method: config.method,
    responsePath: config.responsePath,
    credentialField: config.credentialField,
    credentialName: config.credentialName,
    credentialPlacement: config.credentialPlacement,
    credentialPrefix: config.credentialPrefix,
    credentialSource: credentialSource,
    credentialTemplate: config.credentialTemplate,
    headers: config.headers,
    body: config.body,
    windows: config.windows,
    hadUnsafeUrl: config.hadUnsafeUrl,
    unknownFields: config.unknownFields,
  );

  Future<void> _ensureCliRow(ManagedProvider provider) async {
    final appCubit = _appProviderCubit;
    if (appCubit == null) return;
    final source = provider.endpointConfig.credentialSource.trim();
    final cli = _binding.cliForCredentialSource(source);
    if (cli == null) return;
    final rowId = _binding.rowIdForCredentialSource(source);
    if (rowId == null) return;
    final existing = appCubit.state
        .providersFor(cli)
        .where((row) => row.id == rowId)
        .firstOrNull;
    if (existing != null) return;
    final template = _binding.rowTemplateFor(cli, provider.id, provider.name);
    if (template == null) return;
    await appCubit.upsertProvider(template);
  }

  Future<void> update(ManagedProvider provider) => upsert(provider);

  Future<void> enable(String providerId) => _setEnabled(providerId, true);

  Future<void> disable(String providerId) => _setEnabled(providerId, false);

  Future<void> _setEnabled(String providerId, bool enabled) async {
    if (isClosed) return;
    final id = providerId.trim();
    if (id.isEmpty) return;
    await _serializeMutation(
      () async {
        final provider = state.providerFor(id);
        if (provider == null || provider.enabled == enabled) return;
        _catalogRevision++;
        final next = provider.copyWith(enabled: enabled);
        await _repository.upsert(next);
        _replace(next);
      },
      errorCode: ManagedProviderErrorCode.saveFailed,
      bumpRevision: false,
    );
  }

  Future<void> delete(String providerId) async {
    if (isClosed) return;
    final id = providerId.trim();
    if (id.isEmpty) return;
    await _serializeMutation(() async {
      final provider = state.providerFor(id);
      await _repository.delete(id);
      final cleanupCredentials = _onProviderDeletedCredentialCleanup;
      if (provider != null && cleanupCredentials != null) {
        await cleanupCredentials(provider);
      }
      final onProviderDeletedState = _onProviderDeletedState;
      if (onProviderDeletedState != null) {
        await onProviderDeletedState(id);
      }
      await _removeDedicatedCliRow(provider);
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

  /// Best-effort removal of the entry's dedicated CLI row and its isolated
  /// HOME directory. Failures are logged by the janitor and never fail the
  /// entry deletion.
  Future<void> _removeDedicatedCliRow(ManagedProvider? provider) async {
    final janitor = _rowJanitor;
    if (janitor == null || provider == null) return;
    final source = provider.endpointConfig.credentialSource.trim();
    final cli = _binding.cliForCredentialSource(source);
    final rowId = _binding.rowIdForCredentialSource(source);
    if (cli == null || rowId == null) return;
    await janitor.removeDedicatedRow(cli: cli, rowId: rowId);
  }

  Future<void> _serializeMutation(
    Future<void> Function() action, {
    required ManagedProviderErrorCode errorCode,
    bool bumpRevision = true,
  }) async {
    if (bumpRevision) _catalogRevision++;
    final previous = _mutationTail;
    final release = Completer<void>();
    final queued = previous.then((_) => release.future);
    _mutationTail = queued;
    await previous;
    try {
      await action();
    } on Object {
      if (!isClosed) {
        emit(
          state.copyWith(
            status: ManagedProviderLoadStatus.error,
            errorCode: errorCode,
            errorMessage: null,
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
}
