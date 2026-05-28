import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/mcp_catalog_listing.dart';
import '../models/mcp_registry_source.dart';
import '../services/mcp/mcp_registry_browse_service.dart';
import '../services/mcp/mcp_registry_config_service.dart';
import '../services/mcp/smithery_mcp_service.dart';

enum McpDiscoverySource { builtin, smithery, official }

class McpDiscoveryState extends Equatable {
  const McpDiscoveryState({
    this.source = McpDiscoverySource.builtin,
    this.query = '',
    this.registryConfig,
    this.remoteItems = const [],
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
  final bool loading;
  final String? errorMessage;
  final int smitheryPage;
  final int smitheryTotalPages;
  final String? registryCursor;
  final String? registryNextCursor;

  McpRegistrySourceConfig? get activeRemoteSource {
    final config = registryConfig;
    if (config == null) return null;
    return switch (source) {
      McpDiscoverySource.smithery => config.byKind(McpRegistrySourceKind.smithery),
      McpDiscoverySource.official =>
        config.byKind(McpRegistrySourceKind.officialRegistry),
      McpDiscoverySource.builtin => null,
    };
  }

  bool get remoteDisabled =>
      source != McpDiscoverySource.builtin &&
      (activeRemoteSource == null || !activeRemoteSource!.enabled);

  bool get hasMore => source == McpDiscoverySource.smithery
      ? smitheryPage < smitheryTotalPages
      : (registryNextCursor != null && registryNextCursor!.isNotEmpty);

  McpDiscoveryState copyWith({
    McpDiscoverySource? source,
    String? query,
    McpRegistrySourcesConfig? registryConfig,
    List<McpCatalogListing>? remoteItems,
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
  }) : _registryConfig = registryConfig ?? McpRegistryConfigService(),
       _smithery = smithery ?? SmitheryMcpService(),
       _registry = registry ?? McpRegistryBrowseService(),
       super(const McpDiscoveryState());

  final McpRegistryConfigService _registryConfig;
  final SmitheryMcpService _smithery;
  final McpRegistryBrowseService _registry;

  @override
  Future<void> close() {
    _smithery.close();
    _registry.close();
    return super.close();
  }

  Future<void> initialize() async {
    final config = await _registryConfig.load();
    emit(state.copyWith(registryConfig: config, clearError: true));
    if (state.source != McpDiscoverySource.builtin) {
      await loadRemote(reset: true);
    }
  }

  void setSource(McpDiscoverySource next) {
    if (next == state.source) return;
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
    emit(
      state.copyWith(
        source: next,
        clearError: true,
        smitheryPage: 1,
        clearRegistryCursor: true,
        registryNextCursor: null,
      ),
    );
    loadRemote(reset: true);
  }

  void setQuery(String value) {
    emit(state.copyWith(query: value, clearError: true));
    if (state.source == McpDiscoverySource.builtin) return;
    loadRemote(reset: true);
  }

  Future<void> refreshRemote() => loadRemote(reset: true);

  Future<void> loadRemote({bool reset = true}) async {
    final source = state.activeRemoteSource;
    if (source == null || !source.enabled) {
      emit(
        state.copyWith(
          remoteItems: const [],
          loading: false,
          clearError: true,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        loading: true,
        clearError: true,
        remoteItems: reset ? const [] : state.remoteItems,
        smitheryPage: reset ? 1 : state.smitheryPage,
        registryCursor: reset ? null : state.registryCursor,
        registryNextCursor: reset ? null : state.registryNextCursor,
      ),
    );

    try {
      if (state.source == McpDiscoverySource.smithery) {
        final page = reset ? 1 : state.smitheryPage;
        final result = await _smithery.search(
          state.query,
          baseUrl: source.baseUrl,
          apiToken: source.apiToken,
          page: page,
        );
        emit(
          state.copyWith(
            remoteItems: reset
                ? result.items
                : [...state.remoteItems, ...result.items],
            smitheryPage: result.page,
            smitheryTotalPages: result.totalPages,
            loading: false,
          ),
        );
      } else {
        final cursor = reset ? null : state.registryCursor;
        final result = await _registry.search(
          state.query,
          baseUrl: source.baseUrl,
          cursor: cursor,
        );
        emit(
          state.copyWith(
            remoteItems: reset
                ? result.items
                : [...state.remoteItems, ...result.items],
            registryCursor: cursor,
            registryNextCursor: result.nextCursor,
            loading: false,
          ),
        );
      }
    } catch (e) {
      emit(state.copyWith(loading: false, errorMessage: e.toString()));
    }
  }

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore || state.source == McpDiscoverySource.builtin) {
      return;
    }
    if (state.source == McpDiscoverySource.smithery) {
      emit(state.copyWith(smitheryPage: state.smitheryPage + 1));
    } else {
      emit(state.copyWith(registryCursor: state.registryNextCursor));
    }
    await loadRemote(reset: false);
  }
}
