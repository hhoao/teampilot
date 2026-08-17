import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/catalog/catalog_types.dart';
import '../models/discoverable_team.dart';
import '../models/team_config.dart';
import '../services/catalog/catalog_source_aggregation.dart';
import '../services/team/team_clone_service.dart';
import '../services/team_hub/team_hub_source.dart';

enum TeamHubLoadStatus { idle, loading, ready, error }

@Deprecated('Use CatalogSortKey')
enum TeamSort { name, updated }

typedef FavoritesLoader = Future<Set<String>> Function();
typedef FavoriteToggler = Future<bool> Function(String key);

/// Clones a hub team, with optional clone-time teamMode/cli overrides for
/// manifest-undeclared fields.
typedef TeamCloner =
    Future<CloneResult> Function(
      DiscoverableTeam team, {
      TeamMode? teamMode,
      CliTool? cli,
    });

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
    this.favoritesOnly = false,
    this.search = '',
    this.sort = CatalogSortKey.adoption,
    this.sourceFailures = const [],
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

  /// When true, [TeamHubCubit.visibleTeams] keeps only favorited teams.
  final bool favoritesOnly;
  final String search;
  final CatalogSortKey sort;
  final List<CatalogSourceFailure> sourceFailures;
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
    bool? favoritesOnly,
    String? search,
    CatalogSortKey? sort,
    List<CatalogSourceFailure>? sourceFailures,
    TeamHubLoadStatus? status,
    bool? refreshing,
    String? errorMessage,
    bool clearError = false,
    Set<String>? cloningKeys,
  }) => TeamHubState(
    allTeams: allTeams ?? this.allTeams,
    categories: categories ?? this.categories,
    favorites: favorites ?? this.favorites,
    installedDepIds: installedDepIds ?? this.installedDepIds,
    selectedCategory: clearCategory
        ? null
        : (selectedCategory ?? this.selectedCategory),
    favoritesOnly: favoritesOnly ?? this.favoritesOnly,
    search: search ?? this.search,
    sort: sort ?? this.sort,
    status: status ?? this.status,
    refreshing: refreshing ?? this.refreshing,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    cloningKeys: cloningKeys ?? this.cloningKeys,
    sourceFailures: sourceFailures == null
        ? this.sourceFailures
        : List.unmodifiable(sourceFailures),
  );

  @override
  List<Object?> get props => [
    allTeams,
    categories,
    favorites,
    installedDepIds,
    selectedCategory,
    favoritesOnly,
    search,
    sort,
    status,
    refreshing,
    errorMessage,
    cloningKeys,
    sourceFailures,
  ];
}

class TeamHubCubit extends Cubit<TeamHubState> {
  TeamHubCubit({
    required TeamHubSource source,
    required FavoritesLoader loadFavorites,
    required FavoriteToggler saveFavoriteToggle,
    required TeamCloner cloneTeam,
    InstalledDepIdsLoader? loadInstalledDepIds,
  }) : _source = source,
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
    emit(
      state.copyWith(
        status: state.allTeams.isEmpty
            ? TeamHubLoadStatus.loading
            : state.status,
        refreshing: forceRefresh,
        clearError: true,
      ),
    );
    try {
      final sources = await fetchTeamCatalogSources(
        _source,
        forceRefresh: forceRefresh,
      );
      final aggregate = CatalogSourceAggregator.merge(
        sources,
        const _TeamCatalogAdapter(),
        state.sort,
      );
      final teams = _sortTeams(
        _retainPreviousOnFailure(
          aggregate.items,
          state.allTeams,
          aggregate.failures.isNotEmpty,
        ),
        state.sort,
      );
      final cats = _deriveCategories(teams);
      final favs = await _loadFavorites();
      final installed = await _loadInstalledDepIds?.call() ?? const <String>{};
      final blocking = teams.isEmpty && aggregate.failures.isNotEmpty;
      emit(
        state.copyWith(
          allTeams: teams,
          categories: cats,
          favorites: favs,
          installedDepIds: installed,
          status: blocking ? TeamHubLoadStatus.error : TeamHubLoadStatus.ready,
          refreshing: false,
          sourceFailures: aggregate.failures,
          errorMessage: blocking
              ? aggregate.failures.map((failure) => failure.message).join('; ')
              : null,
          clearError: !blocking,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: TeamHubLoadStatus.error,
          refreshing: false,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  void setSearch(String value) => emit(state.copyWith(search: value));

  void setCategory(String? category) => category == null
      ? emit(state.copyWith(clearCategory: true))
      : emit(state.copyWith(selectedCategory: category));

  void setFavoritesOnly(bool value) =>
      emit(state.copyWith(favoritesOnly: value));

  void setSort(Object sort) {
    final key = switch (sort) {
      CatalogSortKey value => value,
      TeamSort.name => CatalogSortKey.name,
      TeamSort.updated => CatalogSortKey.updated,
      _ => throw ArgumentError.value(sort, 'sort'),
    };
    emit(state.copyWith(sort: key));
  }

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

  /// Clones [team]; tracks the key in `cloningKeys` for spinner UI. Refreshes
  /// [installedDepIds] after a successful clone. May throw [CloneException].
  Future<CloneResult> clone(
    DiscoverableTeam team, {
    TeamMode? teamMode,
    CliTool? cli,
  }) async {
    emit(state.copyWith(cloningKeys: {...state.cloningKeys, team.key}));
    try {
      final result = await _cloneTeam(team, teamMode: teamMode, cli: cli);
      final installed =
          await _loadInstalledDepIds?.call() ?? state.installedDepIds;
      emit(state.copyWith(installedDepIds: installed));
      return result;
    } finally {
      emit(
        state.copyWith(cloningKeys: {...state.cloningKeys}..remove(team.key)),
      );
    }
  }

  void clearError() => emit(state.copyWith(clearError: true));

  /// Applies the active search query + sort to [input].
  List<DiscoverableTeam> _searchAndSort(Iterable<DiscoverableTeam> input) {
    final q = state.search.trim().toLowerCase();
    final list = input.where((t) {
      if (q.isEmpty) return true;
      return t.name.toLowerCase().contains(q) ||
          t.description.toLowerCase().contains(q);
    }).toList();
    final aggregate = CatalogSourceAggregator.merge(
      [
        CatalogSourceResult(
          sourceId: 'visible',
          sourceLabel: 'Visible teams',
          items: list,
        ),
      ],
      const _TeamCatalogAdapter(),
      state.sort,
    );
    return aggregate.items;
  }

  /// Teams visible on the hub page: favorites + category + search + sort, all
  /// applied as inline filters on a single page (no sub-navigation).
  List<DiscoverableTeam> get visibleTeams {
    Iterable<DiscoverableTeam> base = state.selectedCategory == null
        ? state.allTeams
        : state.allTeams.where((t) => t.category == state.selectedCategory);
    if (state.favoritesOnly) {
      base = base.where((t) => state.favorites.contains(t.key));
    }
    return _searchAndSort(base);
  }
}

List<DiscoverableTeam> _retainPreviousOnFailure(
  List<DiscoverableTeam> current,
  List<DiscoverableTeam> previous,
  bool hasFailure,
) {
  if (!hasFailure) return current;
  final keys = current.map((team) => team.key).toSet();
  return [...current, ...previous.where((team) => !keys.contains(team.key))];
}

List<DiscoverableTeam> _sortTeams(
  Iterable<DiscoverableTeam> teams,
  CatalogSortKey sort,
) => CatalogSourceAggregator.merge(
  [
    CatalogSourceResult(
      sourceId: 'sorted',
      sourceLabel: 'Teams',
      items: teams.toList(growable: false),
    ),
  ],
  const _TeamCatalogAdapter(),
  sort,
).items;

List<String> _deriveCategories(List<DiscoverableTeam> teams) {
  final categories = {
    for (final team in teams)
      if (team.category.trim().isNotEmpty) team.category.trim(),
  };
  return categories.toList()..sort();
}

class _TeamCatalogAdapter implements CatalogAdapter<DiscoverableTeam> {
  const _TeamCatalogAdapter();

  @override
  CatalogEntry adapt(DiscoverableTeam team) => _TeamCatalogEntry(team);
}

class _TeamCatalogEntry implements CatalogEntry {
  const _TeamCatalogEntry(this.team);

  final DiscoverableTeam team;

  @override
  String get id => team.key;

  @override
  CatalogResourceKind get kind => CatalogResourceKind.team;

  @override
  String get name => team.name;

  @override
  String get description => team.description;

  @override
  String? get sourceLabel => team.author;

  @override
  String? get author => team.author;

  @override
  List<String> get tags => [team.category];

  @override
  CatalogMetrics get metrics {
    final metrics = team.metrics;
    if (metrics.updatedAtMs != null || team.updatedAt == 0) return metrics;
    return CatalogMetrics(
      adoptionCount: metrics.adoptionCount,
      rating: metrics.rating,
      ratingCount: metrics.ratingCount,
      updatedAtMs: team.updatedAt,
      publishedAtMs: metrics.publishedAtMs,
    );
  }
}
