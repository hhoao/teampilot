import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/discoverable_member.dart';
import '../services/expert_hub/composite_expert_hub_source.dart';
import '../services/expert_hub/member_roster_service.dart';
import 'launch_profile_cubit.dart';

enum ExpertHubLoadStatus { idle, loading, ready, error }

enum MemberSort { name, updated }

typedef FavoritesLoader = Future<Set<String>> Function();
typedef FavoriteToggler = Future<bool> Function(String key);
typedef LaunchProfilesAccessor = LaunchProfileCubit Function();

/// Loads the set of local skill ids already installed, so the detail view can
/// mark each dependency as installed vs to-pull.
typedef InstalledDepIdsLoader = Future<Set<String>> Function();

List<String> _deriveCategories(List<DiscoverableMember> members) {
  final set = <String>{
    for (final m in members)
      if (m.category.trim().isNotEmpty) m.category.trim(),
  };
  return set.toList()..sort();
}

class ExpertHubState extends Equatable {
  const ExpertHubState({
    this.allMembers = const [],
    this.categories = const [],
    this.favorites = const {},
    this.installedDepIds = const {},
    this.selectedCategory,
    this.favoritesOnly = false,
    this.localOnly = false,
    this.teamExtractOnly = false,
    this.search = '',
    this.sort = MemberSort.name,
    this.status = ExpertHubLoadStatus.idle,
    this.refreshing = false,
    this.errorMessage,
    this.addingKeys = const {},
  });

  final List<DiscoverableMember> allMembers;
  final List<String> categories;
  final Set<String> favorites;

  /// Local skill ids already installed (for detail-view badges).
  final Set<String> installedDepIds;
  final String? selectedCategory;

  /// When true, [ExpertHubCubit.visibleMembers] keeps only favorited members.
  final bool favoritesOnly;

  /// When true, keeps only [ExpertMemberSource.local] entries.
  final bool localOnly;

  /// When true, keeps only [ExpertMemberSource.teamExtract] entries.
  final bool teamExtractOnly;
  final String search;
  final MemberSort sort;
  final ExpertHubLoadStatus status;
  final bool refreshing;
  final String? errorMessage;
  final Set<String> addingKeys;

  /// Per-category member counts (ignores the active search/category filter).
  Map<String, int> get categoryCounts {
    final counts = <String, int>{};
    for (final m in allMembers) {
      final c = m.category.trim();
      if (c.isEmpty) continue;
      counts[c] = (counts[c] ?? 0) + 1;
    }
    return counts;
  }

  ExpertHubState copyWith({
    List<DiscoverableMember>? allMembers,
    List<String>? categories,
    Set<String>? favorites,
    Set<String>? installedDepIds,
    String? selectedCategory,
    bool clearCategory = false,
    bool? favoritesOnly,
    bool? localOnly,
    bool? teamExtractOnly,
    String? search,
    MemberSort? sort,
    ExpertHubLoadStatus? status,
    bool? refreshing,
    String? errorMessage,
    bool clearError = false,
    Set<String>? addingKeys,
  }) => ExpertHubState(
    allMembers: allMembers ?? this.allMembers,
    categories: categories ?? this.categories,
    favorites: favorites ?? this.favorites,
    installedDepIds: installedDepIds ?? this.installedDepIds,
    selectedCategory: clearCategory
        ? null
        : (selectedCategory ?? this.selectedCategory),
    favoritesOnly: favoritesOnly ?? this.favoritesOnly,
    localOnly: localOnly ?? this.localOnly,
    teamExtractOnly: teamExtractOnly ?? this.teamExtractOnly,
    search: search ?? this.search,
    sort: sort ?? this.sort,
    status: status ?? this.status,
    refreshing: refreshing ?? this.refreshing,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    addingKeys: addingKeys ?? this.addingKeys,
  );

  @override
  List<Object?> get props => [
    allMembers,
    categories,
    favorites,
    installedDepIds,
    selectedCategory,
    favoritesOnly,
    localOnly,
    teamExtractOnly,
    search,
    sort,
    status,
    refreshing,
    errorMessage,
    addingKeys,
  ];
}

class ExpertHubCubit extends Cubit<ExpertHubState> {
  ExpertHubCubit({
    required CompositeExpertHubSource source,
    required FavoritesLoader loadFavorites,
    required FavoriteToggler saveFavoriteToggle,
    required MemberRosterService memberRosterService,
    required LaunchProfilesAccessor launchProfiles,
    InstalledDepIdsLoader? loadInstalledDepIds,
  }) : _source = source,
       _loadFavorites = loadFavorites,
       _saveFavoriteToggle = saveFavoriteToggle,
       _memberRosterService = memberRosterService,
       _launchProfiles = launchProfiles,
       _loadInstalledDepIds = loadInstalledDepIds,
       super(const ExpertHubState());

  final CompositeExpertHubSource _source;
  final FavoritesLoader _loadFavorites;
  final FavoriteToggler _saveFavoriteToggle;
  final MemberRosterService _memberRosterService;
  final LaunchProfilesAccessor _launchProfiles;
  final InstalledDepIdsLoader? _loadInstalledDepIds;

  Future<void> load({bool forceRefresh = false}) async {
    emit(
      state.copyWith(
        status: state.allMembers.isEmpty
            ? ExpertHubLoadStatus.loading
            : state.status,
        refreshing: forceRefresh,
        clearError: true,
      ),
    );
    try {
      final members = await _source.fetchMembers(forceRefresh: forceRefresh);
      final cats = _deriveCategories(members);
      final favs = await _loadFavorites();
      final installed = await _loadInstalledDepIds?.call() ?? const <String>{};
      emit(
        state.copyWith(
          allMembers: members,
          categories: cats,
          favorites: favs,
          installedDepIds: installed,
          status: ExpertHubLoadStatus.ready,
          refreshing: false,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: ExpertHubLoadStatus.error,
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

  void setLocalOnly(bool value) => emit(state.copyWith(localOnly: value));

  void setTeamExtractOnly(bool value) =>
      emit(state.copyWith(teamExtractOnly: value));

  void setSort(MemberSort sort) => emit(state.copyWith(sort: sort));

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

  /// Adds [member] to [teamId]; tracks the key in `addingKeys` for spinner UI.
  /// Refreshes [installedDepIds] after a successful add. May throw
  /// [MemberAddException].
  Future<MemberAddResult> addToTeam({
    required String teamId,
    required DiscoverableMember member,
  }) async {
    emit(state.copyWith(addingKeys: {...state.addingKeys, member.key}));
    try {
      final result = await _memberRosterService.addExpertToTeam(
        teamId: teamId,
        expert: member,
        launchProfiles: _launchProfiles(),
      );
      final installed =
          await _loadInstalledDepIds?.call() ?? state.installedDepIds;
      emit(state.copyWith(installedDepIds: installed));
      return result;
    } finally {
      emit(
        state.copyWith(addingKeys: {...state.addingKeys}..remove(member.key)),
      );
    }
  }

  void clearError() => emit(state.copyWith(clearError: true));

  /// Applies the active search query + sort to [input].
  List<DiscoverableMember> _searchAndSort(Iterable<DiscoverableMember> input) {
    final q = state.search.trim().toLowerCase();
    final list = input.where((m) {
      if (q.isEmpty) return true;
      return m.name.toLowerCase().contains(q) ||
          m.description.toLowerCase().contains(q) ||
          m.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();
    switch (state.sort) {
      case MemberSort.name:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case MemberSort.updated:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    return list;
  }

  /// Members visible on the hub page: source + favorites + category + search +
  /// sort, all applied as inline filters on a single page (no sub-navigation).
  ///
  /// When [languageCode] is set, display fields are localized via
  /// [DiscoverableMember.forLocale] before filtering/search (category filter
  /// still matches the canonical root category, then display uses localized).
  List<DiscoverableMember> visibleMembers({String languageCode = ''}) {
    final lang = languageCode.trim();
    Iterable<DiscoverableMember> base = state.allMembers;
    if (state.selectedCategory != null) {
      // Filter on canonical (root) category so locale switches do not break
      // an active pill selection.
      base = base.where((m) => m.category == state.selectedCategory);
    }
    if (state.favoritesOnly) {
      base = base.where((m) => state.favorites.contains(m.key));
    }
    if (state.localOnly) {
      base = base.where((m) => m.source == ExpertMemberSource.local);
    }
    if (state.teamExtractOnly) {
      base = base.where((m) => m.source == ExpertMemberSource.teamExtract);
    }
    if (lang.isNotEmpty) {
      base = base.map((m) => m.forLocale(lang));
    }
    return _searchAndSort(base);
  }

  /// Localized label for a canonical [category] key, if any member provides one.
  String categoryLabel(String category, {String languageCode = ''}) {
    final lang = languageCode.trim();
    if (lang.isEmpty) return category;
    for (final m in state.allMembers) {
      if (m.category != category) continue;
      final localized = m.forLocale(lang).category;
      if (localized.isNotEmpty) return localized;
    }
    return category;
  }
}
