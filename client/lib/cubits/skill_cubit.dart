import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/skill.dart';
import '../repositories/skill_repository.dart';
import '../services/skill/skill_fetch_service.dart';
import '../services/skill/skill_install_service.dart';
import '../services/skill/skill_repo_disk_cache_service.dart';
import '../utils/logger.dart';

enum SkillLoadStatus { idle, loading, ready, error }

class SkillsShSearchState extends Equatable {
  const SkillsShSearchState({
    this.query = '',
    this.entries = const [],
    this.totalCount = 0,
    this.offset = 0,
    this.loading = false,
  });
  final String query;
  final List<SkillsShEntry> entries;
  final int totalCount;
  final int offset;
  final bool loading;

  SkillsShSearchState copyWith({
    String? query,
    List<SkillsShEntry>? entries,
    int? totalCount,
    int? offset,
    bool? loading,
  }) => SkillsShSearchState(
    query: query ?? this.query,
    entries: entries ?? this.entries,
    totalCount: totalCount ?? this.totalCount,
    offset: offset ?? this.offset,
    loading: loading ?? this.loading,
  );

  @override
  List<Object?> get props => [query, entries, totalCount, offset, loading];
}

class SkillState extends Equatable {
  const SkillState({
    this.installed = const [],
    this.repos = const [],
    this.discoverable = const [],
    this.updates = const [],
    this.skillsSh = const SkillsShSearchState(),
    this.status = SkillLoadStatus.idle,
    this.errorMessage,
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
  final SkillsShSearchState skillsSh;
  final SkillLoadStatus status;
  final String? errorMessage;
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
    SkillsShSearchState? skillsSh,
    SkillLoadStatus? status,
    String? errorMessage,
    bool clearError = false,
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
    skillsSh: skillsSh ?? this.skillsSh,
    status: status ?? this.status,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
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
    skillsSh,
    status,
    errorMessage,
    busyIds,
    discoveryLoading,
    updatesLoading,
    repoSyncingKeys,
    toolbarBusy,
  ];
}

typedef SkillUninstalledHandler = Future<void> Function(String skillId);

class SkillCubit extends Cubit<SkillState> {
  SkillCubit(this._repo, {SkillUninstalledHandler? onSkillUninstalled})
    : _onSkillUninstalled = onSkillUninstalled,
      super(const SkillState());

  final SkillRepository _repo;
  final SkillUninstalledHandler? _onSkillUninstalled;
  int _discoveryGeneration = 0;

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
      unawaited(refreshDiscoverable());
    } catch (e) {
      appLogger.e('[skills] loadAll failed: $e');
      emit(state.copyWith(status: SkillLoadStatus.error, errorMessage: '$e'));
    }
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
    await _syncReposInBackground(enabled, force: force, clearError: true);
  }

  /// Syncs only [reposToSync] against GitHub; discoverable list includes all enabled repos from disk.
  Future<void> _syncReposInBackground(
    List<SkillRepo> reposToSync, {
    bool force = false,
    bool clearError = false,
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

    final batchKeys = reposToSync.map(SkillRepoDiskCacheService.repoKey).toSet();
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
      emit(
        state.copyWith(
          discoverable: discoverable,
          discoveryLoading: repoSyncingKeys.isNotEmpty,
          repoSyncingKeys: repoSyncingKeys,
        ),
      );
    }

    await Future.wait(
      reposToSync.map((repo) async {
        final key = SkillRepoDiskCacheService.repoKey(repo);
        try {
          await _repo.syncRepoCache(repo, force: force);
        } catch (e) {
          appLogger.w('[skills] sync ${repo.fullName} failed: $e');
        } finally {
          await onRepoSyncFinished(key);
        }
      }),
    );

    if (generation != _discoveryGeneration) return;
    final repoSyncingKeys =
        state.repoSyncingKeys.where((k) => !batchKeys.contains(k)).toSet();
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
      final updated =
          repos.firstWhere((r) => r.owner == repo.owner && r.name == repo.name);
      unawaited(_syncReposInBackground([updated]));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    }
  }

  Future<void> installFromDiscovery(
    DiscoverableSkill d, {
    bool overwrite = false,
  }) async {
    final busy = {...state.busyIds, d.key};
    emit(state.copyWith(busyIds: busy, clearError: true));
    try {
      await _repo.installFromDiscovery(d, overwrite: overwrite);
      final installed = await _repo.loadInstalled();
      emit(state.copyWith(installed: installed));
    } on SkillInstallException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
    } on SkillFetchException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    } finally {
      final next = {...state.busyIds}..remove(d.key);
      emit(state.copyWith(busyIds: next));
    }
  }

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

  Future<void> installSkillsShEntry(
    SkillsShEntry e, {
    bool overwrite = false,
  }) async {
    final d = DiscoverableSkill(
      key: e.key,
      name: e.name,
      description: '',
      directory: e.directory,
      readmeUrl: e.readmeUrl,
      repoOwner: e.repoOwner,
      repoName: e.repoName,
      repoBranch: e.repoBranch,
    );
    await installFromDiscovery(d, overwrite: overwrite);
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

  Future<void> searchSkillsSh(String query) async {
    if (query.trim().length < 2) return;
    emit(
      state.copyWith(
        skillsSh: state.skillsSh.copyWith(
          loading: true,
          query: query,
          offset: 0,
          entries: const [],
        ),
        clearError: true,
      ),
    );
    try {
      final res = await _repo.searchSkillsSh(query, offset: 0);
      emit(
        state.copyWith(
          skillsSh: SkillsShSearchState(
            query: query,
            entries: res.skills,
            totalCount: res.totalCount,
            offset: res.skills.length,
            loading: false,
          ),
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          skillsSh: state.skillsSh.copyWith(loading: false),
          errorMessage: '$e',
        ),
      );
    }
  }

  Future<void> loadMoreSkillsSh() async {
    if (state.skillsSh.loading) return;
    if (state.skillsSh.entries.length >= state.skillsSh.totalCount) return;
    emit(state.copyWith(skillsSh: state.skillsSh.copyWith(loading: true)));
    try {
      final res = await _repo.searchSkillsSh(
        state.skillsSh.query,
        offset: state.skillsSh.offset,
      );
      final merged = [...state.skillsSh.entries, ...res.skills];
      emit(
        state.copyWith(
          skillsSh: state.skillsSh.copyWith(
            entries: merged,
            offset: merged.length,
            totalCount: res.totalCount,
            loading: false,
          ),
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          skillsSh: state.skillsSh.copyWith(loading: false),
          errorMessage: '$e',
        ),
      );
    }
  }

  void clearError() => emit(state.copyWith(clearError: true));
}
