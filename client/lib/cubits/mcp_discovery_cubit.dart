import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/mcp_catalog_listing.dart';
import '../models/mcp_registry_source.dart';
import '../services/mcp/mcp_discovery_disk_cache_service.dart';
import '../services/mcp/mcp_registry_browse_service.dart';
import '../services/mcp/mcp_registry_config_service.dart';
import '../services/mcp/smithery_mcp_service.dart';

enum McpDiscoverySource { all, builtin, smithery, official }

class _RemoteSourceSnapshot {
  List<McpCatalogListing> items = [];
  String query = '';
  int smitheryPage = 1;
  int smitheryTotalPages = 1;
  String? registryCursor;
  String? registryNextCursor;
}

class McpDiscoveryState extends Equatable {
  const McpDiscoveryState({
    this.source = McpDiscoverySource.all,
    this.query = '',
    this.registryConfig,
    this.remoteItems = const [],
    this.smitheryItems = const [],
    this.officialItems = const [],
    this.loading = false,
    this.errorMessage,
    this.smitheryPage = 1,
    this.smitheryTotalPages = 1,
    this.registryCursor,
    this.registryNextCursor,
  });

  final McpDiscoverySource source;
  final String query;
  final McpRegistrySourcesConfig? registryConfig;
  final List<McpCatalogListing> remoteItems;
  final List<McpCatalogListing> smitheryItems;
  final List<McpCatalogListing> officialItems;
  final bool loading;
  final String? errorMessage;
  final int smitheryPage;
  final int smitheryTotalPages;
  final String? registryCursor;
  final String? registryNextCursor;

  McpRegistrySourceConfig? remoteSourceFor(McpDiscoverySource target) {
    final config = registryConfig;
    if (config == null) return null;
    return switch (target) {
      McpDiscoverySource.smithery => config.byKind(McpRegistrySourceKind.smithery),
      McpDiscoverySource.official =>
        config.byKind(McpRegistrySourceKind.officialRegistry),
      McpDiscoverySource.all || McpDiscoverySource.builtin => null,
    };
  }

  McpRegistrySourceConfig? get activeRemoteSource => remoteSourceFor(source);

  bool get remoteDisabled =>
      (source == McpDiscoverySource.smithery ||
          source == McpDiscoverySource.official) &&
      (activeRemoteSource == null || !activeRemoteSource!.enabled);

  bool get hasMore => source == McpDiscoverySource.smithery
      ? smitheryPage < smitheryTotalPages
      : source == McpDiscoverySource.official
      ? (registryNextCursor != null && registryNextCursor!.isNotEmpty)
      : false;

  McpDiscoveryState copyWith({
    McpDiscoverySource? source,
    String? query,
    McpRegistrySourcesConfig? registryConfig,
    List<McpCatalogListing>? remoteItems,
    List<McpCatalogListing>? smitheryItems,
    List<McpCatalogListing>? officialItems,
    bool? loading,
    String? errorMessage,
    bool clearError = false,
    int? smitheryPage,
    int? smitheryTotalPages,
    String? registryCursor,
    String? registryNextCursor,
    bool clearRegistryCursor = false,
  }) => McpDiscoveryState(
    source: source ?? this.source,
    query: query ?? this.query,
    registryConfig: registryConfig ?? this.registryConfig,
    remoteItems: remoteItems ?? this.remoteItems,
    smitheryItems: smitheryItems ?? this.smitheryItems,
    officialItems: officialItems ?? this.officialItems,
    loading: loading ?? this.loading,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    smitheryPage: smitheryPage ?? this.smitheryPage,
    smitheryTotalPages: smitheryTotalPages ?? this.smitheryTotalPages,
    registryCursor: clearRegistryCursor
        ? null
        : (registryCursor ?? this.registryCursor),
    registryNextCursor: registryNextCursor ?? this.registryNextCursor,
  );

  @override
  List<Object?> get props => [
    source,
    query,
    registryConfig,
    remoteItems,
    smitheryItems,
    officialItems,
    loading,
    errorMessage,
    smitheryPage,
    smitheryTotalPages,
    registryCursor,
    registryNextCursor,
  ];
}

class McpDiscoveryCubit extends Cubit<McpDiscoveryState> {
  McpDiscoveryCubit({
    McpRegistryConfigService? registryConfig,
    SmitheryMcpService? smithery,
    McpRegistryBrowseService? registry,
    McpDiscoveryDiskCacheService? diskCache,
  }) : _registryConfig = registryConfig ?? McpRegistryConfigService(),
       _smithery = smithery ?? SmitheryMcpService(),
       _registry = registry ?? McpRegistryBrowseService(),
       _diskCache = diskCache ?? McpDiscoveryDiskCacheService(),
       super(const McpDiscoveryState());

  final McpRegistryConfigService _registryConfig;
  final SmitheryMcpService _smithery;
  final McpRegistryBrowseService _registry;
  final McpDiscoveryDiskCacheService _diskCache;

  final Map<McpDiscoverySource, _RemoteSourceSnapshot> _remoteSnapshots = {
    McpDiscoverySource.smithery: _RemoteSourceSnapshot(),
    McpDiscoverySource.official: _RemoteSourceSnapshot(),
  };

  @override
  Future<void> close() {
    _smithery.close();
    _registry.close();
    return super.close();
  }

  Future<void> initialize() async {
    final config = await _registryConfig.load();
    emit(state.copyWith(registryConfig: config, clearError: true));
    await _hydrateFromDisk();
    await _warmRemoteCaches();
  }

  void setSource(McpDiscoverySource next) {
    if (next == state.source) return;
    _persistActiveRemoteSnapshot();

    if (next == McpDiscoverySource.builtin) {
      emit(
        state.copyWith(
          source: next,
          query: '',
          remoteItems: const [],
          loading: false,
          clearError: true,
          smitheryPage: 1,
          smitheryTotalPages: 1,
          clearRegistryCursor: true,
          registryNextCursor: null,
        ),
      );
      return;
    }

    if (next == McpDiscoverySource.all) {
      emit(
        state.copyWith(
          source: next,
          remoteItems: const [],
          loading: false,
          clearError: true,
        ),
      );
      _warmRemoteCaches();
      return;
    }

    final snapshot = _remoteSnapshots[next]!;
    emit(
      state.copyWith(
        source: next,
        remoteItems: List<McpCatalogListing>.from(snapshot.items),
        smitheryPage: snapshot.smitheryPage,
        smitheryTotalPages: snapshot.smitheryTotalPages,
        registryCursor: snapshot.registryCursor,
        registryNextCursor: snapshot.registryNextCursor,
        loading: false,
        clearError: true,
      ),
    );
    if (snapshot.items.isEmpty || snapshot.query != state.query) {
      loadRemote(reset: true);
    }
  }

  Future<void> setQuery(String value) async {
    emit(state.copyWith(query: value, clearError: true));
    if (state.source == McpDiscoverySource.builtin ||
        state.source == McpDiscoverySource.all) {
      return;
    }
    final source = state.source;
    final snapshot = _remoteSnapshots[source]!;
    if (snapshot.items.isNotEmpty && snapshot.query == value) {
      emit(state.copyWith(remoteItems: List<McpCatalogListing>.from(snapshot.items)));
      return;
    }
    if (value.isEmpty) {
      final cacheKey = _cacheKeyFor(source);
      if (cacheKey != null) {
        await _hydrateSourceFromDisk(source, cacheKey);
        if (snapshot.items.isNotEmpty && snapshot.query.isEmpty) {
          emit(
            state.copyWith(
              remoteItems: List<McpCatalogListing>.from(snapshot.items),
              smitheryPage: snapshot.smitheryPage,
              smitheryTotalPages: snapshot.smitheryTotalPages,
              registryCursor: snapshot.registryCursor,
              registryNextCursor: snapshot.registryNextCursor,
            ),
          );
          return;
        }
      }
    }
    await loadRemote(reset: true);
  }

  Future<void> refreshRemote() async {
    switch (state.source) {
      case McpDiscoverySource.all:
        emit(state.copyWith(loading: true, clearError: true));
        await Future.wait([
          _loadRemoteSource(McpDiscoverySource.smithery, reset: true),
          _loadRemoteSource(McpDiscoverySource.official, reset: true),
        ]);
        emit(state.copyWith(loading: false));
      case McpDiscoverySource.builtin:
        return;
      case McpDiscoverySource.smithery:
      case McpDiscoverySource.official:
        await loadRemote(reset: true);
    }
  }

  Future<void> loadRemote({bool reset = true}) async {
    final source = state.source;
    if (source != McpDiscoverySource.smithery &&
        source != McpDiscoverySource.official) {
      return;
    }
    await _loadRemoteSource(source, reset: reset);
  }

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    if (state.source == McpDiscoverySource.smithery) {
      emit(state.copyWith(smitheryPage: state.smitheryPage + 1));
    } else if (state.source == McpDiscoverySource.official) {
      emit(state.copyWith(registryCursor: state.registryNextCursor));
    } else {
      return;
    }
    await loadRemote(reset: false);
  }

  Future<void> _hydrateFromDisk() async {
    await Future.wait([
      _hydrateSourceFromDisk(
        McpDiscoverySource.smithery,
        mcpDiscoveryCacheSmithery,
      ),
      _hydrateSourceFromDisk(
        McpDiscoverySource.official,
        mcpDiscoveryCacheOfficial,
      ),
    ]);
    emit(
      state.copyWith(
        smitheryItems: List<McpCatalogListing>.from(
          _remoteSnapshots[McpDiscoverySource.smithery]!.items,
        ),
        officialItems: List<McpCatalogListing>.from(
          _remoteSnapshots[McpDiscoverySource.official]!.items,
        ),
      ),
    );
  }

  Future<void> _hydrateSourceFromDisk(
    McpDiscoverySource source,
    String cacheKey,
  ) async {
    final cached = await _diskCache.read(cacheKey);
    if (cached == null || cached.query.isNotEmpty) return;
    final snapshot = _remoteSnapshots[source]!;
    snapshot
      ..items = List<McpCatalogListing>.from(cached.items)
      ..query = cached.query
      ..smitheryPage = cached.smitheryPage
      ..smitheryTotalPages = cached.smitheryTotalPages
      ..registryCursor = cached.registryCursor
      ..registryNextCursor = cached.registryNextCursor;
  }

  Future<void> _warmRemoteCaches() async {
    if (state.loading) return;
    final needsSmithery = _remoteSnapshots[McpDiscoverySource.smithery]!.items.isEmpty;
    final needsOfficial = _remoteSnapshots[McpDiscoverySource.official]!.items.isEmpty;
    if (!needsSmithery && !needsOfficial) return;

    emit(state.copyWith(loading: true, clearError: true));
    await Future.wait([
      if (needsSmithery)
        _loadRemoteSource(McpDiscoverySource.smithery, reset: true),
      if (needsOfficial)
        _loadRemoteSource(McpDiscoverySource.official, reset: true),
    ]);
    emit(state.copyWith(loading: false));
  }

  Future<void> _loadRemoteSource(
    McpDiscoverySource source, {
    required bool reset,
  }) async {
    assert(
      source == McpDiscoverySource.smithery ||
          source == McpDiscoverySource.official,
    );

    final registrySource = state.remoteSourceFor(source);
    if (registrySource == null || !registrySource.enabled) {
      _clearRemoteSnapshot(source);
      _syncSnapshotToState(source);
      return;
    }

    final snapshot = _remoteSnapshots[source]!;
    final query = state.source == source ? state.query : snapshot.query;
    final activeView = state.source == source;

    if (activeView) {
      emit(
        state.copyWith(
          loading: true,
          clearError: true,
          remoteItems: reset ? const [] : state.remoteItems,
          smitheryPage: reset && source == McpDiscoverySource.smithery
              ? 1
              : state.smitheryPage,
          registryCursor: reset && source == McpDiscoverySource.official
              ? null
              : state.registryCursor,
          registryNextCursor: reset && source == McpDiscoverySource.official
              ? null
              : state.registryNextCursor,
        ),
      );
    }

    try {
      if (source == McpDiscoverySource.smithery) {
        final page = reset ? 1 : (activeView ? state.smitheryPage : snapshot.smitheryPage);
        final result = await _smithery.search(
          query,
          baseUrl: registrySource.baseUrl,
          apiToken: registrySource.apiToken,
          page: page,
        );
        snapshot.items = reset
            ? result.items
            : [...snapshot.items, ...result.items];
        snapshot.query = query;
        snapshot.smitheryPage = result.page;
        snapshot.smitheryTotalPages = result.totalPages;
        snapshot.registryCursor = null;
        snapshot.registryNextCursor = null;

        emit(
          state.copyWith(
            smitheryItems: List<McpCatalogListing>.from(snapshot.items),
            remoteItems: activeView
                ? List<McpCatalogListing>.from(snapshot.items)
                : state.remoteItems,
            smitheryPage: result.page,
            smitheryTotalPages: result.totalPages,
            loading: activeView ? false : state.loading,
            clearError: true,
          ),
        );
      } else {
        final cursor = reset
            ? null
            : (activeView ? state.registryCursor : snapshot.registryCursor);
        final result = await _registry.search(
          query,
          baseUrl: registrySource.baseUrl,
          cursor: cursor,
        );
        snapshot.items = reset
            ? result.items
            : [...snapshot.items, ...result.items];
        snapshot.query = query;
        snapshot.registryCursor = cursor;
        snapshot.registryNextCursor = result.nextCursor;

        emit(
          state.copyWith(
            officialItems: List<McpCatalogListing>.from(snapshot.items),
            remoteItems: activeView
                ? List<McpCatalogListing>.from(snapshot.items)
                : state.remoteItems,
            registryCursor: cursor,
            registryNextCursor: result.nextCursor,
            loading: activeView ? false : state.loading,
            clearError: true,
          ),
        );
      }
      await _persistSnapshotToDisk(source);
    } catch (e) {
      if (activeView) {
        emit(state.copyWith(loading: false, errorMessage: e.toString()));
      }
    }
  }

  void _persistActiveRemoteSnapshot() {
    final source = state.source;
    if (source != McpDiscoverySource.smithery &&
        source != McpDiscoverySource.official) {
      return;
    }
    final snapshot = _remoteSnapshots[source]!;
    snapshot.items = List<McpCatalogListing>.from(state.remoteItems);
    snapshot.query = state.query;
    snapshot.smitheryPage = state.smitheryPage;
    snapshot.smitheryTotalPages = state.smitheryTotalPages;
    snapshot.registryCursor = state.registryCursor;
    snapshot.registryNextCursor = state.registryNextCursor;
    _syncSnapshotToState(source);
    unawaited(_persistSnapshotToDisk(source));
  }

  Future<void> _persistSnapshotToDisk(McpDiscoverySource source) async {
    final cacheKey = _cacheKeyFor(source);
    if (cacheKey == null) return;
    final snapshot = _remoteSnapshots[source]!;
    if (snapshot.query.isNotEmpty) return;
    await _diskCache.write(
      sourceKey: cacheKey,
      snapshot: McpDiscoveryDiskSnapshot(
        items: List<McpCatalogListing>.from(snapshot.items),
        query: snapshot.query,
        syncedAtMs: DateTime.now().millisecondsSinceEpoch,
        smitheryPage: snapshot.smitheryPage,
        smitheryTotalPages: snapshot.smitheryTotalPages,
        registryCursor: snapshot.registryCursor,
        registryNextCursor: snapshot.registryNextCursor,
      ),
    );
  }

  void _syncSnapshotToState(McpDiscoverySource source) {
    final snapshot = _remoteSnapshots[source]!;
    emit(
      state.copyWith(
        smitheryItems: source == McpDiscoverySource.smithery
            ? List<McpCatalogListing>.from(snapshot.items)
            : state.smitheryItems,
        officialItems: source == McpDiscoverySource.official
            ? List<McpCatalogListing>.from(snapshot.items)
            : state.officialItems,
      ),
    );
  }

  void _clearRemoteSnapshot(McpDiscoverySource source) {
    final snapshot = _remoteSnapshots[source]!;
    snapshot
      ..items = []
      ..query = ''
      ..smitheryPage = 1
      ..smitheryTotalPages = 1
      ..registryCursor = null
      ..registryNextCursor = null;
    _syncSnapshotToState(source);
    final cacheKey = _cacheKeyFor(source);
    if (cacheKey != null) {
      unawaited(_diskCache.delete(cacheKey));
    }
    if (state.source == source) {
      emit(state.copyWith(remoteItems: const [], loading: false, clearError: true));
    }
  }

  String? _cacheKeyFor(McpDiscoverySource source) => switch (source) {
    McpDiscoverySource.smithery => mcpDiscoveryCacheSmithery,
    McpDiscoverySource.official => mcpDiscoveryCacheOfficial,
    McpDiscoverySource.all || McpDiscoverySource.builtin => null,
  };
}
