import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/catalog/catalog_types.dart';
import '../models/discoverable_team.dart';
import '../models/progress_activity.dart';
import '../models/skill.dart';
import '../models/skill_registry_source.dart';
import '../models/unified_skill_entry.dart';
import '../repositories/skill_repository.dart';
import '../services/discovery/discovery_refresh_policy.dart';
import '../services/catalog/catalog_error_sanitizer.dart';
import '../services/catalog/catalog_sort_comparator.dart';
import '../services/progress_activity/pack_acquire_activity_adapter.dart';
import '../services/skill/marketplace/skill_marketplace_source.dart';
import '../services/skill/registry/api_registry_source.dart';
import '../services/skill/registry/git_repo_registry_source.dart';
import '../services/skill/registry/skill_registry_config_service.dart';
import '../services/skill/registry/skill_registry_source.dart';
import '../services/skill/skill_acquisition_engine.dart';
import '../services/skill/skill_repo_disk_cache_service.dart';
import '../utils/logging/logger.dart';
import 'discovery_settings_cubit.dart';

enum SkillLoadStatus { idle, loading, ready, error }

class SkillState extends Equatable {
  const SkillState({
    this.installed = const [],
    this.discoverable = const [],
    this.updates = const [],
    this.registriesConfig = const SkillRegistriesConfig(sources: []),
    this.sources = const [],
    this.discoveryEntries = const [],
    this.discoveryPages = const {},
    this.discoveryHasNext = const {},
    this.discoveryTotals = const {},
    this.discoverySort = CatalogSortKey.adoption,
    List<CatalogSourceFailure> discoveryFailures = const [],
    this.discoveryError,
    this.discoveryBrowsing = false,
    this.discoveryLastQuery,
    this.status = SkillLoadStatus.idle,
    this.errorMessage,
    this.noticeMessage,
    this.busyIds = const {},
    this.discoveryLoading = false,
    this.updatesLoading = false,
    this.repoSyncingKeys = const {},
    this.toolbarBusy = false,
  }) : _discoveryFailures = discoveryFailures;

  final List<Skill> installed;
  final List<DiscoverableSkill> discoverable;
  final List<SkillUpdateInfo> updates;
  final SkillRegistriesConfig registriesConfig;
  final List<SkillRegistrySource> sources;
  final List<UnifiedSkillEntry> discoveryEntries;
  final Map<String, int> discoveryPages;
  final Map<String, bool> discoveryHasNext;
  final Map<String, int> discoveryTotals;
  final CatalogSortKey discoverySort;
  final List<CatalogSourceFailure> _discoveryFailures;
  final String? discoveryError;
  final bool discoveryBrowsing;
  final SkillRegistryQuery? discoveryLastQuery;
  final SkillLoadStatus status;
  final String? errorMessage;
  final String? noticeMessage;
  final Set<String> busyIds;
  final bool discoveryLoading;
  final bool updatesLoading;
  final Set<String> repoSyncingKeys;
  final bool toolbarBusy;

  List<CatalogSourceFailure> get discoveryFailures =>
      List.unmodifiable(_discoveryFailures);

  bool get anyDiscoveryHasNext => discoveryHasNext.values.any((v) => v);

  SkillState copyWith({
    List<Skill>? installed,
    List<DiscoverableSkill>? discoverable,
    List<SkillUpdateInfo>? updates,
    SkillRegistriesConfig? registriesConfig,
    List<SkillRegistrySource>? sources,
    List<UnifiedSkillEntry>? discoveryEntries,
    Map<String, int>? discoveryPages,
    Map<String, bool>? discoveryHasNext,
    Map<String, int>? discoveryTotals,
    CatalogSortKey? discoverySort,
    List<CatalogSourceFailure>? discoveryFailures,
    Object? discoveryError = _discoveryErrorUnset,
    bool? discoveryBrowsing,
    SkillRegistryQuery? discoveryLastQuery,
    SkillLoadStatus? status,
    String? errorMessage,
    bool clearError = false,
    String? noticeMessage,
    bool clearNotice = false,
    Set<String>? busyIds,
    bool? discoveryLoading,
    bool? updatesLoading,
    Set<String>? repoSyncingKeys,
    bool? toolbarBusy,
  }) => SkillState(
    installed: installed ?? this.installed,
    discoverable: discoverable ?? this.discoverable,
    updates: updates ?? this.updates,
    registriesConfig: registriesConfig ?? this.registriesConfig,
    sources: sources ?? this.sources,
    discoveryEntries: discoveryEntries ?? this.discoveryEntries,
    discoveryPages: discoveryPages ?? this.discoveryPages,
    discoveryHasNext: discoveryHasNext ?? this.discoveryHasNext,
    discoveryTotals: discoveryTotals ?? this.discoveryTotals,
    discoverySort: discoverySort ?? this.discoverySort,
    discoveryFailures: discoveryFailures == null
        ? this.discoveryFailures
        : List.unmodifiable(discoveryFailures),
    discoveryError: identical(discoveryError, _discoveryErrorUnset)
        ? this.discoveryError
        : discoveryError as String?,
    discoveryBrowsing: discoveryBrowsing ?? this.discoveryBrowsing,
    discoveryLastQuery: discoveryLastQuery ?? this.discoveryLastQuery,
    status: status ?? this.status,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    noticeMessage: clearNotice ? null : (noticeMessage ?? this.noticeMessage),
    busyIds: busyIds ?? this.busyIds,
    discoveryLoading: discoveryLoading ?? this.discoveryLoading,
    updatesLoading: updatesLoading ?? this.updatesLoading,
    repoSyncingKeys: repoSyncingKeys ?? this.repoSyncingKeys,
    toolbarBusy: toolbarBusy ?? this.toolbarBusy,
  );

  static const _discoveryErrorUnset = Object();

  @override
  List<Object?> get props => [
    installed,
    discoverable,
    updates,
    registriesConfig,
    sources,
    discoveryEntries,
    discoveryPages,
    discoveryHasNext,
    discoveryTotals,
    discoverySort,
    discoveryFailures,
    discoveryError,
    discoveryBrowsing,
    discoveryLastQuery,
    status,
    errorMessage,
    noticeMessage,
    busyIds,
    discoveryLoading,
    updatesLoading,
    repoSyncingKeys,
    toolbarBusy,
  ];
}

typedef SkillUninstalledHandler = Future<void> Function(String skillId);

class SkillCubit extends Cubit<SkillState> {
  SkillCubit(
    this._repo, {
    required this.registryConfigService,
    required List<SkillRegistrySource> initialSources,
    required List<SkillRegistrySource> Function(SkillRegistriesConfig)
    rebuildSources,
    SkillAcquisitionEngine? acquisitionEngine,
    SkillUninstalledHandler? onSkillUninstalled,
    PackAcquireActivityAdapter? packAcquireActivity,
    DiscoverySettingsCubit? discoverySettings,
  }) : _rebuildSources = rebuildSources,
       _acquisitionEngine =
           acquisitionEngine ??
           SkillAcquisitionEngine(
             installGitDir: (d, {bool overwrite = false, String? idOverride}) =>
                 _repo.installFromDiscovery(
                   d,
                   overwrite: overwrite,
                   idOverride: idOverride,
                 ),
             registerDirectory:
                 ({required String id, required String directory}) => _repo
                     .install
                     .registerInstalledDirectory(id: id, directory: directory),
             repoCache: _repo.repoCache,
           ),
       _onSkillUninstalled = onSkillUninstalled,
       _packAcquireActivity = packAcquireActivity,
       _discoverySettings = discoverySettings,
       super(SkillState(sources: initialSources));

  final SkillRepository _repo;
  final SkillRegistryConfigService registryConfigService;
  final SkillAcquisitionEngine _acquisitionEngine;
  final SkillUninstalledHandler? _onSkillUninstalled;
  final PackAcquireActivityAdapter? _packAcquireActivity;
  final DiscoverySettingsCubit? _discoverySettings;
  final List<SkillRegistrySource> Function(SkillRegistriesConfig)
  _rebuildSources;
  int _discoveryGeneration = 0;
  Future<void> _inflightRepoSync = Future.value();

  bool _autoRefreshEnabled() =>
      _discoverySettings?.state.autoRefreshEnabled ?? false;

  @override
  Future<void> close() async {
    _discoveryGeneration++;
    await _inflightRepoSync;
    return super.close();
  }

  Future<void> loadAll() async {
    emit(state.copyWith(status: SkillLoadStatus.loading, clearError: true));
    try {
      final installed = await _repo.loadInstalled();
      final config = await registryConfigService.load();
      final sources = _rebuildSources(config);
      emit(
        state.copyWith(
          installed: installed,
          registriesConfig: config,
          sources: sources,
          status: SkillLoadStatus.ready,
        ),
      );
    } catch (e) {
      appLogger.e('[skills] loadAll failed: $e');
      emit(state.copyWith(status: SkillLoadStatus.error, errorMessage: '$e'));
    }
  }

  /// Loads discovery when the Discovery tab opens: disk cache first; remote
  /// sync only for first-time (no cache) repos when auto-refresh is off, or
  /// per [kDiscoveryAutoRefreshTtl] when it is on. [force] always syncs.
  Future<void> ensureDiscoveryLoaded({bool force = false}) async {
    if (!force && state.discoveryLoading) return;
    if (!force && state.repoSyncingKeys.isNotEmpty) return;
    if (force) {
      await refreshDiscoverable(force: true);
      return;
    }
    if (_autoRefreshEnabled()) {
      await refreshDiscoverable(force: false);
      return;
    }
    if (state.discoverable.isNotEmpty) return;
    await _syncMissingReposOnce();
  }

  /// 手动模式（默认）：只对从未同步过的 repo 做一次初始化同步，
  /// 有磁盘缓存的 repo 不发网络请求。
  Future<void> _syncMissingReposOnce() async {
    final enabled = _gitRepos();
    final missing = <SkillRepo>[];
    for (final repo in enabled) {
      if (!await _repo.hasCachedSnapshot(repo)) missing.add(repo);
    }
    if (missing.isEmpty) {
      emit(
        state.copyWith(
          discoveryLoading: false,
          repoSyncingKeys: const {},
          discoverable: await _aggregateDiscoverableFromDisk(enabled),
        ),
      );
      return;
    }
    await _syncReposInBackground(missing, force: true, clearError: true);
  }

  Future<void> refreshDiscoverable({bool force = false}) async {
    final enabled = _gitRepos();
    if (enabled.isEmpty) {
      emit(
        state.copyWith(
          discoveryLoading: false,
          discoverable: const [],
          repoSyncingKeys: const {},
        ),
      );
      return;
    }
    await _syncReposInBackground(
      enabled,
      force: force,
      clearError: true,
      maxStaleness: force
          ? null
          : (_autoRefreshEnabled() ? kDiscoveryAutoRefreshTtl : null),
    );
  }

  /// Syncs only [reposToSync] against GitHub; discoverable list includes all enabled repos from disk.
  Future<void> _syncReposInBackground(
    List<SkillRepo> reposToSync, {
    bool force = false,
    bool clearError = false,
    Duration? maxStaleness,
  }) async {
    if (reposToSync.isEmpty || isClosed) return;

    final generation = ++_discoveryGeneration;
    final sync = _runReposSyncInBackground(
      reposToSync,
      generation: generation,
      force: force,
      clearError: clearError,
      maxStaleness: maxStaleness,
    );
    _inflightRepoSync = sync;
    await sync;
  }

  Future<void> _runReposSyncInBackground(
    List<SkillRepo> reposToSync, {
    required int generation,
    required bool force,
    required bool clearError,
    required Duration? maxStaleness,
  }) async {
    if (isClosed) return;
    final enabled = _gitRepos();
    var syncing = {
      ...state.repoSyncingKeys,
      ...reposToSync.map(SkillRepoDiskCacheService.repoKey),
    };
    emit(
      state.copyWith(
        discoveryLoading: true,
        discoverable: await _aggregateDiscoverableFromDisk(enabled),
        repoSyncingKeys: syncing,
        clearError: clearError,
      ),
    );

    final batchKeys = reposToSync
        .map(SkillRepoDiskCacheService.repoKey)
        .toSet();
    final remaining = Set<String>.from(batchKeys);

    Future<void> onRepoSyncFinished(String key) async {
      if (isClosed || generation != _discoveryGeneration) return;
      remaining.remove(key);
      final discoverable = await _aggregateDiscoverableFromDisk(_gitRepos());
      if (isClosed || generation != _discoveryGeneration) return;
      final repoSyncingKeys = {
        ...state.repoSyncingKeys.where((k) => !batchKeys.contains(k)),
        ...remaining,
      };
      _emitDiscoveryProgress(
        discoverable: discoverable,
        discoveryLoading: repoSyncingKeys.isNotEmpty,
        repoSyncingKeys: repoSyncingKeys,
      );
    }

    await Future.wait(
      reposToSync.map((repo) async {
        final key = SkillRepoDiskCacheService.repoKey(repo);
        try {
          if (isClosed) return;
          await _repo.syncRepoCache(
            repo,
            force: force,
            maxStaleness: maxStaleness,
          );
        } catch (e) {
          appLogger.w('[skills] sync ${repo.fullName} failed: $e');
        } finally {
          try {
            await onRepoSyncFinished(key);
          } catch (e) {
            appLogger.w('[skills] sync ${repo.fullName} progress failed: $e');
          }
        }
      }),
    );

    if (isClosed || generation != _discoveryGeneration) return;
    final repoSyncingKeys = state.repoSyncingKeys
        .where((k) => !batchKeys.contains(k))
        .toSet();
    emit(
      state.copyWith(
        discoveryLoading: false,
        repoSyncingKeys: repoSyncingKeys,
        discoverable: await _aggregateDiscoverableFromDisk(_gitRepos()),
      ),
    );
  }

  void _emitDiscoveryProgress({
    required List<DiscoverableSkill> discoverable,
    required bool discoveryLoading,
    required Set<String> repoSyncingKeys,
  }) {
    final discoverableChanged = !_sameDiscoverableSkills(
      state.discoverable,
      discoverable,
    );
    final syncingChanged = state.repoSyncingKeys != repoSyncingKeys;
    final loadingChanged = state.discoveryLoading != discoveryLoading;
    if (isClosed) return;
    emit(
      state.copyWith(
        discoverable: discoverableChanged ? discoverable : null,
        discoveryLoading: discoveryLoading,
        repoSyncingKeys: repoSyncingKeys,
      ),
    );
  }

  static bool _sameDiscoverableSkills(
    List<DiscoverableSkill> a,
    List<DiscoverableSkill> b,
  ) {
    if (a.length != b.length) return false;
    final keysA = a
        .map((s) => '${s.directory}:${s.repoOwner}:${s.repoName}')
        .toSet();
    return keysA.length == a.length &&
        b.every(
          (s) => keysA.contains('${s.directory}:${s.repoOwner}:${s.repoName}'),
        );
  }

  Future<List<DiscoverableSkill>> _aggregateDiscoverableFromDisk(
    List<SkillRepo> enabled,
  ) async {
    final seen = <String>{};
    final out = <DiscoverableSkill>[];
    for (final repo in enabled) {
      for (final d in await _repo.readCachedDiscoverable(repo)) {
        final key = '${d.directory}:${d.repoOwner}:${d.repoName}';
        if (seen.add(key)) out.add(d);
      }
    }
    return out;
  }

  List<SkillRepo> _gitRepos() => [
    for (final s in state.sources)
      if (s is GitRepoRegistrySource && s.enabled) s.gitRepo,
  ];

  Future<void> installFromDiscovery(
    DiscoverableSkill d, {
    bool overwrite = false,
  }) async {
    final busyId = d.key;
    final busy = {...state.busyIds, busyId};
    emit(state.copyWith(busyIds: busy, clearError: true));
    try {
      await _runPackAcquireTracked(
        title: 'Installing skill: ${d.name}',
        historyMessage: 'Installed ${d.name}',
        run: (_) => _installDiscoverableCore(d, overwrite: overwrite),
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    } finally {
      final next = {...state.busyIds}..remove(busyId);
      emit(state.copyWith(busyIds: next));
    }
  }

  Future<void> _installDiscoverableCore(
    DiscoverableSkill d, {
    required bool overwrite,
  }) async {
    final result = await _acquisitionEngine.installDiscoverable(
      d,
      overwrite: overwrite,
    );
    if (!result.success) {
      throw StateError(result.message);
    }
    await _emitInstalled();
  }

  Future<void> _runPackAcquireTracked({
    required String title,
    required String historyMessage,
    required Future<void> Function(PackAcquireStepReporter onStep) run,
  }) async {
    final adapter = _packAcquireActivity;
    if (adapter == null) {
      await run(({subtitle, completedSteps, totalSteps}) {});
      return;
    }
    await adapter.runTracked<void>(
      kind: ProgressActivityKind.packAcquire,
      title: title,
      historyMessageFor: (_) => historyMessage,
      run: run,
    );
  }

  /// TeamHub clone path: install one template skill dep and refresh cubit state.
  /// Failures are non-blocking for the caller; returns null on error.
  Future<String?> installTeamDependency(SkillDependencyRef ref) async {
    final busyId = ref.expectedLocalId;
    final busy = {...state.busyIds, busyId};
    emit(state.copyWith(busyIds: busy, clearError: true));
    try {
      if (state.installed.any((s) => s.id == busyId)) {
        return busyId;
      }

      final result = await _acquisitionEngine.install(ref);
      if (result.success) {
        await _emitInstalled();
        return result.skillId;
      }
      if (_isAlreadyExistsMessage(result.message)) {
        await _emitInstalled();
        return ref.expectedLocalId;
      }
      appLogger.w('[team-hub] skill dep ${ref.name} failed: ${result.message}');
      return null;
    } catch (e) {
      if (_isAlreadyExistsMessage('$e')) {
        await _emitInstalled();
        return ref.expectedLocalId;
      }
      appLogger.w('[team-hub] skill dep ${ref.name} failed: $e');
      return null;
    } finally {
      final next = {...state.busyIds}..remove(busyId);
      emit(state.copyWith(busyIds: next));
    }
  }

  Future<void> _emitInstalled() async {
    final installed = await _repo.loadInstalled();
    emit(state.copyWith(installed: installed));
  }

  static bool _isAlreadyExistsMessage(String message) =>
      message.toLowerCase().contains('already exists');

  Future<void> installFromZip(File zip) async {
    if (state.toolbarBusy) return;
    emit(state.copyWith(toolbarBusy: true, clearError: true));
    try {
      await _repo.installFromZip(zip);
      final installed = await _repo.loadInstalled();
      emit(state.copyWith(installed: installed));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    } finally {
      emit(state.copyWith(toolbarBusy: false));
    }
  }

  static const marketplaceRepoAddedNoticeKey = 'skillsMarketplaceRepoAdded';
  static const _unifiedPageSize = 20;

  List<SkillRegistrySource> get _enabledSources =>
      state.sources.where((s) => s.enabled).toList();

  Future<void> unifiedBrowse() async {
    await unifiedSearch('', sourceId: null);
  }

  void setDiscoverySort(CatalogSortKey sort) {
    if (sort == state.discoverySort) return;
    emit(
      state.copyWith(
        discoverySort: sort,
        discoveryEntries: _sortDiscoveryEntries(state.discoveryEntries, sort),
      ),
    );
  }

  Future<void> unifiedSearch(
    String query, {
    String? sourceId,
    String? category,
    String? occupation,
    String? language,
    String? sortBy,
  }) async {
    final q = query.trim();
    final effectiveQ = q.length >= 2 ? q : '';
    final sources = sourceId != null
        ? state.sources.where((s) => s.id == sourceId && s.enabled).toList()
        : _enabledSources;
    if (sources.isEmpty) {
      emit(
        state.copyWith(
          discoveryEntries: const [],
          discoveryPages: const {},
          discoveryHasNext: const {},
          discoveryTotals: const {},
          discoveryFailures: const [],
          discoveryError: null,
          discoveryBrowsing: effectiveQ.isEmpty,
          discoveryLoading: false,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        discoveryLoading: true,
        discoveryBrowsing: effectiveQ.isEmpty,
        discoveryError: null,
      ),
    );
    final lastQuery = SkillRegistryQuery(
      query: effectiveQ,
      page: 1,
      limit: _unifiedPageSize,
      category: category,
      occupation: occupation,
      language: language,
      sortBy: sortBy,
    );
    final results = await Future.wait(
      sources.map((s) async {
        try {
          final page = await s.search(lastQuery);
          return (source: s, page: page, failure: null);
        } catch (e) {
          return (
            source: s,
            page: SkillRegistryPage(entries: const [], hasNext: false),
            failure: _catalogFailure(s, e),
          );
        }
      }),
    );
    if (!isClosed) {
      final failures = [
        for (final result in results)
          if (result.failure != null) result.failure!,
      ];
      final failedSourceIds = failures
          .map((failure) => failure.sourceId)
          .toSet();
      final retained = _sameDiscoveryQuery(state.discoveryLastQuery, lastQuery)
          ? state.discoveryEntries
                .where((entry) => failedSourceIds.contains(entry.sourceId))
                .toList()
          : null;
      final merged = _mergeEntries(results, appendTo: retained);
      emit(
        state.copyWith(
          discoveryEntries: merged.entries,
          discoveryPages: {
            for (final r in results) r.source.id: r.failure == null ? 1 : 0,
          },
          discoveryHasNext: {
            for (final r in results) r.source.id: r.page.hasNext,
          },
          discoveryTotals: {for (final r in results) r.source.id: r.page.total},
          discoveryLastQuery: lastQuery,
          discoveryFailures: failures,
          discoveryError: merged.entries.isEmpty && failures.isNotEmpty
              ? failures.first.message
              : null,
          discoveryLoading: false,
        ),
      );
    }
  }

  Future<void> unifiedLoadMore() async {
    if (state.discoveryLoading) return;
    if (!state.anyDiscoveryHasNext) return;
    emit(state.copyWith(discoveryLoading: true));
    final last =
        state.discoveryLastQuery ??
        SkillRegistryQuery(page: 1, limit: _unifiedPageSize);
    final nextPages = <String, int>{};
    final results = await Future.wait(
      _enabledSources.map((s) async {
        final loaded = state.discoveryPages[s.id] ?? 0;
        final hasNext = state.discoveryHasNext[s.id] ?? false;
        if (loaded == 0 || !hasNext) {
          return (
            source: s,
            page: SkillRegistryPage(entries: const [], hasNext: false),
            failure: null,
          );
        }
        final next = loaded + 1;
        try {
          final page = await s.search(
            SkillRegistryQuery(
              query: last.query,
              page: next,
              limit: last.limit,
              category: last.category,
              occupation: last.occupation,
              language: last.language,
              sortBy: last.sortBy,
            ),
          );
          nextPages[s.id] = next;
          return (source: s, page: page, failure: null);
        } catch (e) {
          return (
            source: s,
            page: SkillRegistryPage(
              entries: const [],
              hasNext: state.discoveryHasNext[s.id] ?? false,
            ),
            failure: _catalogFailure(s, e),
          );
        }
      }),
    );
    if (!isClosed) {
      final merged = _mergeEntries(results, appendTo: state.discoveryEntries);
      final failures = [
        for (final result in results)
          if (result.failure != null) result.failure!,
      ];
      emit(
        state.copyWith(
          discoveryEntries: merged.entries,
          discoveryPages: {...state.discoveryPages, ...nextPages},
          discoveryHasNext: {
            ...state.discoveryHasNext,
            for (final r in results) r.source.id: r.page.hasNext,
          },
          discoveryFailures: failures,
          discoveryError: failures.isNotEmpty ? failures.first.message : null,
          discoveryLoading: false,
        ),
      );
    }
  }

  ({List<UnifiedSkillEntry> entries}) _mergeEntries(
    List<
      ({
        SkillRegistrySource source,
        SkillRegistryPage page,
        CatalogSourceFailure? failure,
      })
    >
    results, {
    List<UnifiedSkillEntry>? appendTo,
  }) {
    final seen = <String>{};
    final out = <UnifiedSkillEntry>[
      if (appendTo != null) ...appendTo.where((e) => seen.add(e.dedupeKey)),
    ];
    for (final r in results) {
      for (final skill in r.page.entries) {
        final entry = UnifiedSkillEntry(
          skill: skill,
          sourceId: r.source.id,
          repoKey: r.source is GitRepoRegistrySource
              ? SkillRepoDiskCacheService.repoKey(
                  (r.source as GitRepoRegistrySource).gitRepo,
                )
              : null,
        );
        if (seen.add(entry.dedupeKey)) out.add(entry);
      }
    }
    return (entries: _sortDiscoveryEntries(out, state.discoverySort));
  }

  CatalogSourceFailure _catalogFailure(
    SkillRegistrySource source,
    Object error,
  ) {
    final message = error is MarketplaceQuotaException
        ? marketplaceQuotaErrorKey
        : CatalogErrorSanitizer.sanitize('$error');
    return CatalogSourceFailure(
      sourceId: source.id,
      sourceLabel: source.label,
      message: message,
    );
  }

  bool _sameDiscoveryQuery(SkillRegistryQuery? a, SkillRegistryQuery b) {
    return a != null &&
        a.query == b.query &&
        a.category == b.category &&
        a.occupation == b.occupation &&
        a.language == b.language &&
        a.sortBy == b.sortBy;
  }

  List<UnifiedSkillEntry> _sortDiscoveryEntries(
    List<UnifiedSkillEntry> entries,
    CatalogSortKey sort,
  ) {
    final sorted = [...entries];
    sorted.sort(
      (a, b) => CatalogSortComparator.compare(
        _UnifiedSkillCatalogEntry(a),
        _UnifiedSkillCatalogEntry(b),
        sort,
      ),
    );
    return sorted;
  }

  Future<void> unifiedSetApiKey(String sourceId, String key) async {
    final cfg = state.registriesConfig.byId(sourceId);
    if (cfg == null || cfg.kind != SkillRegistryKind.api) return;
    await _applyConfig(
      SkillRegistriesConfig(
        sources: [
          for (final s in state.registriesConfig.sources)
            s.id == sourceId
                ? s.copyWith(
                    clearApiToken: key.trim().isEmpty,
                    apiToken: key.trim().isEmpty ? null : key.trim(),
                  )
                : s,
        ],
      ),
    );
    emit(state.copyWith(discoveryError: null));
  }

  /// Probes [candidate] (the in-dialog form edits, not the persisted source).
  /// Returns `null` on success, the error string on failure. Does NOT emit
  /// `errorMessage` — the management dialog owns the toast.
  Future<String?> testRegistryConnection(
    SkillRegistrySourceConfig candidate,
  ) async {
    final exists = state.sources.any((s) => s.id == candidate.id);
    if (!exists) return 'source-not-found';
    try {
      final probe = switch (candidate.kind) {
        SkillRegistryKind.api => ApiRegistrySource(candidate),
        SkillRegistryKind.gitRepo => GitRepoRegistrySource(
          candidate,
          discoverableProvider: () => _repo.readCachedDiscoverable(
            SkillRepo(
              owner: candidate.gitOwner ?? '',
              name: candidate.gitName ?? '',
              branch: candidate.gitBranch ?? 'main',
            ),
          ),
          syncNow: () async {
            await _repo.syncRepoCache(
              SkillRepo(
                owner: candidate.gitOwner ?? '',
                name: candidate.gitName ?? '',
                branch: candidate.gitBranch ?? 'main',
              ),
              force: true,
            );
          },
        ),
      };
      await probe.testConnection();
      return null;
    } catch (e) {
      return '$e';
    }
  }

  Future<bool> addRegistrySource(SkillRegistrySourceConfig cfg) async {
    if (state.registriesConfig.byId(cfg.id) != null) return false;
    await _applyConfig(
      SkillRegistriesConfig(sources: [...state.registriesConfig.sources, cfg]),
    );
    if (cfg.kind == SkillRegistryKind.gitRepo && cfg.enabled) {
      await _syncReposInBackground([
        SkillRepo(
          owner: cfg.gitOwner ?? '',
          name: cfg.gitName ?? '',
          branch: cfg.gitBranch ?? 'main',
        ),
      ]);
    }
    return true;
  }

  Future<void> updateRegistrySource(SkillRegistrySourceConfig cfg) async {
    // Capture pre-update state before `_applyConfig` (which rebuilds `state.sources`).
    // Skip the background sync only when the source was ALREADY an enabled git
    // source whose repo (owner/name/branch) is unchanged.
    var oldIsGit = false;
    var repoChanged = false;
    final newRepo = SkillRepo(
      owner: cfg.gitOwner ?? '',
      name: cfg.gitName ?? '',
      branch: cfg.gitBranch ?? 'main',
    );
    for (final s in state.sources) {
      if (s.id == cfg.id && s is GitRepoRegistrySource) {
        oldIsGit = s.enabled;
        final old = s.gitRepo;
        repoChanged =
            old.owner != newRepo.owner ||
            old.name != newRepo.name ||
            old.branch != newRepo.branch;
        break;
      }
    }
    final next = SkillRegistriesConfig(
      sources: [
        for (final s in state.registriesConfig.sources)
          s.id == cfg.id ? cfg : s,
      ],
    );
    await _applyConfig(next);
    if (cfg.kind == SkillRegistryKind.gitRepo &&
        cfg.enabled &&
        (!oldIsGit || repoChanged)) {
      unawaited(_syncReposInBackground([newRepo]));
    }
  }

  Future<void> removeRegistrySource(String id) async {
    final cfg = state.registriesConfig.byId(id);
    if (cfg == null) return;
    if (cfg.kind == SkillRegistryKind.gitRepo) {
      await _repo.deleteRepoCache(
        SkillRepo(
          owner: cfg.gitOwner ?? '',
          name: cfg.gitName ?? '',
          branch: cfg.gitBranch ?? 'main',
        ),
      );
    }
    await _applyConfig(
      SkillRegistriesConfig(
        sources: [
          for (final s in state.registriesConfig.sources)
            if (s.id != id) s,
        ],
      ),
    );
  }

  Future<void> toggleRegistrySource(String id, bool enabled) async {
    final cfg = state.registriesConfig.byId(id);
    if (cfg == null) return;
    await updateRegistrySource(cfg.copyWith(enabled: enabled));
  }

  Future<void> _applyConfig(SkillRegistriesConfig config) async {
    await registryConfigService.save(config);
    final sources = _rebuildSources(config);
    if (!isClosed) {
      emit(state.copyWith(registriesConfig: config, sources: sources));
    }
  }

  Future<void> installUnifiedEntry(UnifiedSkillEntry e) async {
    final skill = e.skill;
    if (state.busyIds.contains(skill.key)) return;
    emit(
      state.copyWith(busyIds: {...state.busyIds, skill.key}, clearError: true),
    );
    try {
      if (skill.isInstalledDirectly) {
        await _acquisitionEngine.installGitDir(
          DiscoverableSkill(
            key: skill.key,
            name: skill.name,
            description: skill.description,
            directory: skill.directory!,
            readmeUrl: skill.githubUrl,
            repoOwner: skill.repoOwner,
            repoName: skill.repoName,
            repoBranch: skill.repoBranch,
          ),
        );
        final installed = await _repo.loadInstalled();
        emit(state.copyWith(installed: installed));
      } else {
        final added = await addRegistrySource(
          SkillRegistrySourceConfig(
            id: 'git-${skill.repoOwner}-${skill.repoName}',
            kind: SkillRegistryKind.gitRepo,
            label: '${skill.repoOwner}/${skill.repoName}',
            gitOwner: skill.repoOwner,
            gitName: skill.repoName,
            gitBranch: skill.repoBranch,
          ),
        );
        if (added) {
          emit(state.copyWith(noticeMessage: marketplaceRepoAddedNoticeKey));
        }
      }
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    } finally {
      final next = {...state.busyIds}..remove(skill.key);
      emit(state.copyWith(busyIds: next));
    }
  }

  Future<void> uninstall(Skill s) async {
    if (state.busyIds.contains(s.id)) return;
    emit(state.copyWith(busyIds: {...state.busyIds, s.id}, clearError: true));
    try {
      await _repo.uninstall(s);
      final installed = await _repo.loadInstalled();
      emit(state.copyWith(installed: installed));
      await _onSkillUninstalled?.call(s.id);
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    } finally {
      final next = {...state.busyIds}..remove(s.id);
      emit(state.copyWith(busyIds: next));
    }
  }

  Future<void> toggleSkillEnabled(Skill s, bool enabled) async {
    try {
      await _repo.toggleSkillEnabled(s, enabled);
      final installed = await _repo.loadInstalled();
      emit(state.copyWith(installed: installed));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    }
  }

  Future<void> checkUpdates() async {
    emit(state.copyWith(updatesLoading: true));
    try {
      final updates = await _repo.checkUpdates(state.installed);
      emit(state.copyWith(updates: updates, updatesLoading: false));
    } catch (e) {
      emit(state.copyWith(updatesLoading: false, errorMessage: '$e'));
    }
  }

  Future<void> updateSkill(Skill s) async {
    emit(state.copyWith(busyIds: {...state.busyIds, s.id}, clearError: true));
    try {
      await _repo.updateSkill(s);
      final installed = await _repo.loadInstalled();
      final updates = state.updates.where((u) => u.id != s.id).toList();
      emit(state.copyWith(installed: installed, updates: updates));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    } finally {
      final next = {...state.busyIds}..remove(s.id);
      emit(state.copyWith(busyIds: next));
    }
  }

  Future<void> updateAll() async {
    if (state.toolbarBusy) return;
    emit(state.copyWith(toolbarBusy: true, clearError: true));
    try {
      for (final u in List<SkillUpdateInfo>.from(state.updates)) {
        final match = state.installed.where((s) => s.id == u.id).toList();
        if (match.isEmpty) continue;
        final skill = match.first;
        if (skill.repoOwner == null) continue;
        await updateSkill(skill);
      }
    } finally {
      emit(state.copyWith(toolbarBusy: false));
    }
  }

  Future<List<UnmanagedSkill>> scanUnmanaged() async {
    try {
      return await _repo.scanUnmanaged();
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
      return const [];
    }
  }

  Future<void> importUnmanaged(List<UnmanagedSkill> sel) async {
    if (state.toolbarBusy) return;
    emit(state.copyWith(toolbarBusy: true, clearError: true));
    try {
      await _repo.importUnmanaged(sel);
      final installed = await _repo.loadInstalled();
      emit(state.copyWith(installed: installed));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    } finally {
      emit(state.copyWith(toolbarBusy: false));
    }
  }

  void clearError() =>
      emit(state.copyWith(clearError: true, clearNotice: true));
}

class _UnifiedSkillCatalogEntry implements CatalogEntry {
  _UnifiedSkillCatalogEntry(this.entry);

  final UnifiedSkillEntry entry;

  MarketplaceSkill get skill => entry.skill;

  @override
  String get id => skill.key;

  @override
  CatalogResourceKind get kind => CatalogResourceKind.skill;

  @override
  String get name => skill.name;

  @override
  String get description => skill.description;

  @override
  String? get sourceLabel => entry.sourceId;

  @override
  String? get author => skill.repoOwner;

  @override
  List<String> get tags => const [];

  @override
  CatalogMetrics get metrics => skill.metrics;
}
