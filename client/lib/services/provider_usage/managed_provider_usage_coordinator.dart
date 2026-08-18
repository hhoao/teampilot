import '../../models/managed_provider.dart';
import '../../models/provider_usage_snapshot.dart';
import '../../repositories/managed_provider_repository.dart';
import '../../repositories/managed_provider_usage_repository.dart';
import 'managed_provider_usage_adapter.dart';
import 'managed_provider_usage_registry.dart';

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
    // Every all-refresh establishes a new generation. Results from targeted
    // requests started before this point are consequently unable to commit.
    final generation = ++_generation;
    final current = _providers.values.toList(growable: false);
    final results = await Future.wait(
      current.map((provider) => _refreshLoadedProvider(provider, generation)),
    );
    return results;
  }

  /// Invalidates an in-flight provider request. Dart HTTP transports may not
  /// be cancellable, so the generation/token check discards its result.
  void cancelForProvider(String providerId) {
    final id = providerId.trim();
    if (id.isEmpty) return;
    _tokens[id] = (_tokens[id] ?? 0) + 1;
    _pending.remove(id);
  }

  Future<ProviderUsageSnapshot> _refreshLoadedProvider(
    ManagedProvider provider,
    int generation,
  ) {
    final id = provider.id;
    final previousPending = _pending[id];
    if (previousPending != null && previousPending.generation == generation) {
      return previousPending.future;
    }

    final token = (_tokens[id] ?? 0) + 1;
    _tokens[id] = token;
    final future = _executeRefresh(provider, generation, token);
    final pending = _PendingRefresh(
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

  Future<ProviderUsageSnapshot> _executeRefresh(
    ManagedProvider provider,
    int generation,
    int token,
  ) async {
    final previous = _snapshots[provider.id];
    if (!provider.enabled) {
      final result = _unsupportedSnapshot(provider.id, previous);
      if (_isCurrentConfig(provider, generation, token)) {
        _snapshots[provider.id] = result;
        await _usageRepository.save(result);
      }
      return result;
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

    if (!_isCurrent(provider, generation, token)) {
      return _snapshots[provider.id] ?? previous ?? result;
    }
    _snapshots[provider.id] = result;
    await _usageRepository.save(result);
    return result;
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

  bool _isCurrentConfig(ManagedProvider provider, int generation, int token) =>
      generation == _generation &&
      token == _tokens[provider.id] &&
      identical(_providers[provider.id], provider);

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
  const _PendingRefresh({
    required this.generation,
    required this.token,
    required this.future,
  });

  final int generation;
  final int token;
  final Future<ProviderUsageSnapshot> future;
}
