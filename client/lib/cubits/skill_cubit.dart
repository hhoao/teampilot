import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/discoverable_team.dart';
import '../models/progress_activity.dart';
import '../models/skill.dart';
import '../repositories/skill_repository.dart';
import '../services/discovery/discovery_refresh_policy.dart';
import '../services/progress_activity/pack_acquire_activity_adapter.dart';
import '../services/skill/marketplace/skill_marketplace_source.dart';
import '../services/skill/skill_acquisition_engine.dart';
import '../services/skill/skill_repo_disk_cache_service.dart';
import '../utils/logging/logger.dart';
import 'discovery_settings_cubit.dart';

enum SkillLoadStatus { idle, loading, ready, error }

class MarketplaceSearchState extends Equatable {
  const MarketplaceSearchState({
    this.query = '',
    this.page = 1,
    this.loading = false,
    this.error,
    this.entries = const [],
    this.hasNext = false,
    this.total = 0,
    this.category,
    this.occupation,
    this.language,
    this.sortBy,
  });

  final String query;
  final int page;
  final bool loading;
  final String? error;
  final List<MarketplaceSkill> entries;
  final bool hasNext;
  final int total;
  final String? category;
  final String? occupation;
  final String? language;
  final String? sortBy;

  MarketplaceSearchState copyWith({
    String? query,
    int? page,
    bool? loading,
    String? error,
    bool clearError = false,
    List<MarketplaceSkill>? entries,
    bool? hasNext,
    int? total,
    String? category,
    String? occupation,
    String? language,
    String? sortBy,
  }) => MarketplaceSearchState(
    query: query ?? this.query,
    page: page ?? this.page,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    entries: entries ?? this.entries,
    hasNext: hasNext ?? this.hasNext,
    total: total ?? this.total,
    category: category ?? this.category,
    occupation: occupation ?? this.occupation,
    language: language ?? this.language,
    sortBy: sortBy ?? this.sortBy,
  );

  @override
  List<Object?> get props => [
    query,
    page,
    loading,
    error,
    entries,
    hasNext,
    total,
    category,
    occupation,
    language,
    sortBy,
  ];
}

class SkillState extends Equatable {
  const SkillState({
    this.installed = const [],
    this.repos = const [],
    this.discoverable = const [],
    this.updates = const [],
    this.marketplace = const {},
    this.status = SkillLoadStatus.idle,
    this.errorMessage,
    this.noticeMessage,
    this.busyIds = const {},
    this.discoveryLoading = false,
    this.updatesLoading = false,
    this.repoSyncingKeys = const {},
    this.toolbarBusy = false,
  });

  final List<Skill> installed;
  final List<SkillRepo> repos;
  final List<DiscoverableSkill> discoverable;
  final List<SkillUpdateInfo> updates;
  final Map<String, MarketplaceSearchState> marketplace;
  final SkillLoadStatus status;
  final String? errorMessage;
  final String? noticeMessage;
  final Set<String> busyIds;
  final bool discoveryLoading;
  final bool updatesLoading;
  final Set<String> repoSyncingKeys;
  final bool toolbarBusy;

  SkillState copyWith({
    List<Skill>? installed,
    List<SkillRepo>? repos,
    List<DiscoverableSkill>? discoverable,
    List<SkillUpdateInfo>? updates,
    Map<String, MarketplaceSearchState>? marketplace,
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
    repos: repos ?? this.repos,
    discoverable: discoverable ?? this.discoverable,
    updates: updates ?? this.updates,
    marketplace: marketplace ?? this.marketplace,
    status: status ?? this.status,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    noticeMessage: clearNotice ? null : (noticeMessage ?? this.noticeMessage),
    busyIds: busyIds ?? this.busyIds,
    discoveryLoading: discoveryLoading ?? this.discoveryLoading,
    updatesLoading: updatesLoading ?? this.updatesLoading,
    repoSyncingKeys: repoSyncingKeys ?? this.repoSyncingKeys,
    toolbarBusy: toolbarBusy ?? this.toolbarBusy,
  );

  @override
  List<Object?> get props => [
    installed,
    repos,
    discoverable,
    updates,
    marketplace,
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
    this.marketplaces = const [],
    SkillAcquisitionEngine? acquisitionEngine,
    SkillUninstalledHandler? onSkillUninstalled,
    PackAcquireActivityAdapter? packAcquireActivity,
    DiscoverySettingsCubit? discoverySettings,
  }) : _acquisitionEngine =
           acquisitionEngine ??
           SkillAcquisitionEngine(
             installGitDir: (d, {bool overwrite = false, String? idOverride}) =>
                 _repo.installFromDiscovery(
                   d,
                   overwrite: overwrite,
                   idOverride: idOverride,
                 ),
             registerDirectory: ({required String id, required String directory}) =>
                 _repo.install.registerInstalledDirectory(
                   id: id,
                   directory: directory,
                 ),
             repoCache: _repo.repoCache,
           ),
       _onSkillUninstalled = onSkillUninstalled,
       _packAcquireActivity = packAcquireActivity,
       _discoverySettings = discoverySettings,
       super(const SkillState());

  final SkillRepository _repo;
  final SkillAcquisitionEngine _acquisitionEngine;
  final SkillUninstalledHandler? _onSkillUninstalled;
  final PackAcquireActivityAdapter? _packAcquireActivity;
  final DiscoverySettingsCubit? _discoverySettings;
  final List<SkillMarketplaceSource> marketplaces;
  int _discoveryGeneration = 0;

  bool _autoRefreshEnabled() =>
      _discoverySettings?.state.autoRefreshEnabled ?? false;

  Future<void> loadAll() async {
    emit(state.copyWith(status: SkillLoadStatus.loading, clearError: true));
    try {
      final results = await Future.wait([
        _repo.loadInstalled(),
        _repo.loadRepos(),
      ]);
      final installed = results[0] as List<Skill>;
      final repos = results[1] as List<SkillRepo>;
      emit(
        state.copyWith(
          installed: installed,
          repos: repos,
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
    if (!force && state.discoverable.isNotEmpty) return;
    if (force) {
      await refreshDiscoverable(force: true);
      return;
    }
    if (_autoRefreshEnabled()) {
      await refreshDiscoverable(force: false);
      return;
    }
    await _syncMissingReposOnce();
  }

  /// 手动模式（默认）：只对从未同步过的 repo 做一次初始化同步，
  /// 有磁盘缓存的 repo 不发网络请求。
  Future<void> _syncMissingReposOnce() async {
    final enabled = state.repos.where((r) => r.enabled).toList();
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
    final enabled = state.repos.where((r) => r.enabled).toList();
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
    if (reposToSync.isEmpty) return;

    final generation = ++_discoveryGeneration;
    final enabled = state.repos.where((r) => r.enabled).toList();
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
      if (generation != _discoveryGeneration) return;
      remaining.remove(key);
      final discoverable = await _aggregateDiscoverableFromDisk(
        state.repos.where((r) => r.enabled).toList(),
      );
      if (generation != _discoveryGeneration) return;
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
          await _repo.syncRepoCache(
            repo,
            force: force,
            maxStaleness: maxStaleness,
          );
        } catch (e) {
          appLogger.w('[skills] sync ${repo.fullName} failed: $e');
        } finally {
          await onRepoSyncFinished(key);
        }
      }),
    );

    if (generation != _discoveryGeneration) return;
    final repoSyncingKeys = state.repoSyncingKeys
        .where((k) => !batchKeys.contains(k))
        .toSet();
    emit(
      state.copyWith(
        discoveryLoading: false,
        repoSyncingKeys: repoSyncingKeys,
        discoverable: await _aggregateDiscoverableFromDisk(
          state.repos.where((r) => r.enabled).toList(),
        ),
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
    if (!discoverableChanged && !syncingChanged && !loadingChanged) return;
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

  Future<void> addRepo(SkillRepo repo) async {
    try {
      await _repo.repos.addRepo(repo);
      final repos = await _repo.loadRepos();
      emit(state.copyWith(repos: repos));
      if (repo.enabled) {
        unawaited(_syncReposInBackground([repo]));
      }
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    }
  }

  Future<void> removeRepo(String owner, String name) async {
    try {
      await _repo.deleteRepoCache(
        SkillRepo(owner: owner, name: name, branch: 'main'),
      );
      await _repo.repos.removeRepo(owner, name);
      final repos = await _repo.loadRepos();
      final key = SkillRepoDiskCacheService.repoKey(
        SkillRepo(owner: owner, name: name, branch: 'main'),
      );
      final discoverable = state.discoverable
          .where((d) => d.repoOwner != owner || d.repoName != name)
          .toList();
      final syncing = Set.of(state.repoSyncingKeys)..remove(key);
      emit(
        state.copyWith(
          repos: repos,
          discoverable: discoverable,
          repoSyncingKeys: syncing,
        ),
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    }
  }

  Future<void> toggleRepoEnabled(SkillRepo repo, bool enabled) async {
    try {
      await _repo.repos.setEnabled(repo.owner, repo.name, enabled);
      final repos = await _repo.loadRepos();
      if (!enabled) {
        final cacheKey = SkillRepoDiskCacheService.repoKey(repo);
        final discoverable = state.discoverable
            .where((d) => d.repoOwner != repo.owner || d.repoName != repo.name)
            .toList();
        final syncing = Set.of(state.repoSyncingKeys)..remove(cacheKey);
        emit(
          state.copyWith(
            repos: repos,
            discoverable: discoverable,
            repoSyncingKeys: syncing,
          ),
        );
        return;
      }
      final enabledRepos = repos.where((r) => r.enabled).toList();
      emit(
        state.copyWith(
          repos: repos,
          discoverable: await _aggregateDiscoverableFromDisk(enabledRepos),
        ),
      );
      final updated = repos.firstWhere(
        (r) => r.owner == repo.owner && r.name == repo.name,
      );
      unawaited(_syncReposInBackground([updated]));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    }
  }

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
      appLogger.w(
        '[team-hub] skill dep ${ref.name} failed: ${result.message}',
      );
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
  static const _marketplacePageSize = 20;

  SkillMarketplaceSource? _marketplaceById(String sourceId) {
    for (final s in marketplaces) {
      if (s.id == sourceId) return s;
    }
    return null;
  }

  Future<void> searchMarketplace(
    String sourceId, {
    required String query,
    String? category,
    String? occupation,
    String? language,
    String? sortBy,
  }) async {
    final source = _marketplaceById(sourceId);
    if (source == null) return;
    if (query.trim().length < 2) return;
    final slot = state.marketplace[sourceId] ?? const MarketplaceSearchState();
    emit(
      state.copyWith(
        marketplace: {
          ...state.marketplace,
          sourceId: slot.copyWith(
            loading: true,
            query: query,
            page: 1,
            entries: const [],
            hasNext: false,
            clearError: true,
            category: category,
            occupation: occupation,
            language: language,
            sortBy: sortBy,
          ),
        },
        clearError: true,
      ),
    );
    try {
      final res = await source.search(
        MarketplaceSearchQuery(
          query: query,
          page: 1,
          limit: _marketplacePageSize,
          category: category,
          occupation: occupation,
          language: language,
          sortBy: sortBy,
        ),
      );
      emit(
        state.copyWith(
          marketplace: {
            ...state.marketplace,
            sourceId: MarketplaceSearchState(
              query: query,
              page: 1,
              entries: res.skills,
              hasNext: res.hasNext,
              total: res.total,
              category: category,
              occupation: occupation,
              language: language,
              sortBy: sortBy,
            ),
          },
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          marketplace: {
            ...state.marketplace,
            sourceId: slot.copyWith(
              loading: false,
              error: e is MarketplaceQuotaException
                  ? marketplaceQuotaErrorKey
                  : '$e',
            ),
          },
        ),
      );
    }
  }

  Future<void> loadMoreMarketplace(String sourceId) async {
    final source = _marketplaceById(sourceId);
    if (source == null) return;
    final slot = state.marketplace[sourceId];
    if (slot == null || slot.loading || !slot.hasNext) return;
    emit(
      state.copyWith(
        marketplace: {
          ...state.marketplace,
          sourceId: slot.copyWith(loading: true),
        },
      ),
    );
    try {
      final res = await source.search(
        MarketplaceSearchQuery(
          query: slot.query,
          page: slot.page + 1,
          limit: _marketplacePageSize,
          category: slot.category,
          occupation: slot.occupation,
          language: slot.language,
          sortBy: slot.sortBy,
        ),
      );
      emit(
        state.copyWith(
          marketplace: {
            ...state.marketplace,
            sourceId: slot.copyWith(
              page: slot.page + 1,
              entries: [...slot.entries, ...res.skills],
              hasNext: res.hasNext,
              total: res.total,
              loading: false,
            ),
          },
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          marketplace: {
            ...state.marketplace,
            sourceId: slot.copyWith(
              loading: false,
              error: e is MarketplaceQuotaException
                  ? marketplaceQuotaErrorKey
                  : '$e',
            ),
          },
        ),
      );
    }
  }

  Future<void> installMarketplaceEntry(MarketplaceSkill e) async {
    if (state.busyIds.contains(e.key)) return;
    emit(state.copyWith(busyIds: {...state.busyIds, e.key}, clearError: true));
    try {
      if (e.isInstalledDirectly) {
        await _acquisitionEngine.installGitDir(
          DiscoverableSkill(
            key: e.key,
            name: e.name,
            description: e.description,
            directory: e.directory!,
            readmeUrl: e.githubUrl,
            repoOwner: e.repoOwner,
            repoName: e.repoName,
            repoBranch: e.repoBranch,
          ),
        );
        final installed = await _repo.loadInstalled();
        emit(state.copyWith(installed: installed));
      } else {
        await _repo.repos.addRepo(
          SkillRepo(
            owner: e.repoOwner,
            name: e.repoName,
            branch: e.repoBranch,
          ),
        );
        emit(state.copyWith(noticeMessage: marketplaceRepoAddedNoticeKey));
      }
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    } finally {
      final next = {...state.busyIds}..remove(e.key);
      emit(state.copyWith(busyIds: next));
    }
  }

  Future<void> setMarketplaceApiKey(String sourceId, String key) async {
    final source = _marketplaceById(sourceId);
    if (source == null) return;
    await source.setApiKey(key);
    clearMarketplaceError(sourceId);
  }

  void clearMarketplaceError(String sourceId) {
    final slot = state.marketplace[sourceId];
    if (slot == null || slot.error == null) return;
    emit(
      state.copyWith(
        marketplace: {...state.marketplace, sourceId: slot.copyWith(clearError: true)},
      ),
    );
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

  void clearError() => emit(state.copyWith(clearError: true, clearNotice: true));
}
