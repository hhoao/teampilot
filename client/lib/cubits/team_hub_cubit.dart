import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/discoverable_team.dart';
import '../services/team/team_clone_service.dart';
import '../services/team_hub/team_hub_source.dart';

enum TeamHubLoadStatus { idle, loading, ready, error }

enum TeamSort { name, updated }

typedef FavoritesLoader = Future<Set<String>> Function();
typedef FavoriteToggler = Future<bool> Function(String key);
typedef TeamCloner = Future<CloneResult> Function(DiscoverableTeam team);

/// Loads the set of local skill/plugin/MCP ids already installed, so the detail
/// view can mark each dependency as installed vs to-pull.
typedef InstalledDepIdsLoader = Future<Set<String>> Function();

class TeamHubState extends Equatable {
  const TeamHubState({
    this.allTeams = const [],
    this.categories = const [],
    this.favorites = const {},
    this.installedDepIds = const {},
    this.selectedCategory,
    this.search = '',
    this.sort = TeamSort.name,
    this.status = TeamHubLoadStatus.idle,
    this.refreshing = false,
    this.errorMessage,
    this.cloningKeys = const {},
  });

  final List<DiscoverableTeam> allTeams;
  final List<String> categories;
  final Set<String> favorites;

  /// Local skill/plugin/MCP ids already installed (for detail-view badges).
  final Set<String> installedDepIds;
  final String? selectedCategory;
  final String search;
  final TeamSort sort;
  final TeamHubLoadStatus status;
  final bool refreshing;
  final String? errorMessage;
  final Set<String> cloningKeys;

  /// Per-category team counts (ignores the active search/category filter).
  Map<String, int> get categoryCounts {
    final counts = <String, int>{};
    for (final t in allTeams) {
      final c = t.category.trim();
      if (c.isEmpty) continue;
      counts[c] = (counts[c] ?? 0) + 1;
    }
    return counts;
  }

  TeamHubState copyWith({
    List<DiscoverableTeam>? allTeams,
    List<String>? categories,
    Set<String>? favorites,
    Set<String>? installedDepIds,
    String? selectedCategory,
    bool clearCategory = false,
    String? search,
    TeamSort? sort,
    TeamHubLoadStatus? status,
    bool? refreshing,
    String? errorMessage,
    bool clearError = false,
    Set<String>? cloningKeys,
  }) =>
      TeamHubState(
        allTeams: allTeams ?? this.allTeams,
        categories: categories ?? this.categories,
        favorites: favorites ?? this.favorites,
        installedDepIds: installedDepIds ?? this.installedDepIds,
        selectedCategory:
            clearCategory ? null : (selectedCategory ?? this.selectedCategory),
        search: search ?? this.search,
        sort: sort ?? this.sort,
        status: status ?? this.status,
        refreshing: refreshing ?? this.refreshing,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        cloningKeys: cloningKeys ?? this.cloningKeys,
      );

  @override
  List<Object?> get props => [
        allTeams,
        categories,
        favorites,
        installedDepIds,
        selectedCategory,
        search,
        sort,
        status,
        refreshing,
        errorMessage,
        cloningKeys,
      ];
}

class TeamHubCubit extends Cubit<TeamHubState> {
  TeamHubCubit({
    required TeamHubSource source,
    required FavoritesLoader loadFavorites,
    required FavoriteToggler saveFavoriteToggle,
    required TeamCloner cloneTeam,
    InstalledDepIdsLoader? loadInstalledDepIds,
  })  : _source = source,
        _loadFavorites = loadFavorites,
        _saveFavoriteToggle = saveFavoriteToggle,
        _cloneTeam = cloneTeam,
        _loadInstalledDepIds = loadInstalledDepIds,
        super(const TeamHubState());

  final TeamHubSource _source;
  final FavoritesLoader _loadFavorites;
  final FavoriteToggler _saveFavoriteToggle;
  final TeamCloner _cloneTeam;
  final InstalledDepIdsLoader? _loadInstalledDepIds;

  Future<void> load({bool forceRefresh = false}) async {
    emit(state.copyWith(
      status: state.allTeams.isEmpty
          ? TeamHubLoadStatus.loading
          : state.status,
      refreshing: forceRefresh,
      clearError: true,
    ));
    try {
      final teams = await _source.fetchTeams(forceRefresh: forceRefresh);
      final cats = await _source.categories();
      final favs = await _loadFavorites();
      final installed = await _loadInstalledDepIds?.call() ?? const <String>{};
      emit(state.copyWith(
        allTeams: teams,
        categories: cats,
        favorites: favs,
        installedDepIds: installed,
        status: TeamHubLoadStatus.ready,
        refreshing: false,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: TeamHubLoadStatus.error,
        refreshing: false,
        errorMessage: e.toString(),
      ));
    }
  }

  void setSearch(String value) => emit(state.copyWith(search: value));

  void setCategory(String? category) => category == null
      ? emit(state.copyWith(clearCategory: true))
      : emit(state.copyWith(selectedCategory: category));

  void setSort(TeamSort sort) => emit(state.copyWith(sort: sort));

  Future<void> toggleFavorite(String key) async {
    final nowOn = await _saveFavoriteToggle(key);
    final favs = {...state.favorites};
    if (nowOn) {
      favs.add(key);
    } else {
      favs.remove(key);
    }
    emit(state.copyWith(favorites: favs));
  }

  /// Clones [team]; the caller handles navigation/snackbar from the result
  /// (including partial-dependency-failure messaging). Tracks the key in
  /// `cloningKeys` for spinner UI. May throw [CloneException].
  Future<CloneResult> clone(DiscoverableTeam team) async {
    emit(state.copyWith(cloningKeys: {...state.cloningKeys, team.key}));
    try {
      return await _cloneTeam(team);
    } finally {
      emit(state.copyWith(
        cloningKeys: {...state.cloningKeys}..remove(team.key),
      ));
    }
  }

  void clearError() => emit(state.copyWith(clearError: true));

  /// Applies the active search query + sort to [input]. Category filtering is
  /// the caller's choice (applied for Discovery, skipped for Favorites).
  List<DiscoverableTeam> _searchAndSort(Iterable<DiscoverableTeam> input) {
    final q = state.search.trim().toLowerCase();
    final list = input.where((t) {
      if (q.isEmpty) return true;
      return t.name.toLowerCase().contains(q) ||
          t.description.toLowerCase().contains(q);
    }).toList();
    switch (state.sort) {
      case TeamSort.name:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case TeamSort.updated:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    return list;
  }

  /// Teams visible in the Discovery view (category + search + sort applied).
  List<DiscoverableTeam> get visibleTeams => _searchAndSort(
        state.selectedCategory == null
            ? state.allTeams
            : state.allTeams.where((t) => t.category == state.selectedCategory),
      );

  /// Favorited teams (search + sort applied; category ignored).
  List<DiscoverableTeam> get favoriteTeams => _searchAndSort(
        state.allTeams.where((t) => state.favorites.contains(t.key)),
      );
}
