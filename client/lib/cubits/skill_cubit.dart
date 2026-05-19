import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/skill.dart';
import '../repositories/skill_repository.dart';
import '../services/skill_fetch_service.dart';
import '../services/skill_install_service.dart';
import '../services/skill_repo_disk_cache_service.dart';
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
    this.backups = const [],
    this.skillsSh = const SkillsShSearchState(),
    this.status = SkillLoadStatus.idle,
    this.errorMessage,
    this.busyIds = const {},
    this.discoveryLoading = false,
    this.updatesLoading = false,
    this.repoSyncingKeys = const {},
  });

  final List<Skill> installed;
  final List<SkillRepo> repos;
  final List<DiscoverableSkill> discoverable;
  final List<SkillUpdateInfo> updates;
  final List<SkillBackup> backups;
  final SkillsShSearchState skillsSh;
  final SkillLoadStatus status;
  final String? errorMessage;
  final Set<String> busyIds;
  final bool discoveryLoading;
  final bool updatesLoading;
  final Set<String> repoSyncingKeys;

  SkillState copyWith({
    List<Skill>? installed,
    List<SkillRepo>? repos,
    List<DiscoverableSkill>? discoverable,
    List<SkillUpdateInfo>? updates,
    List<SkillBackup>? backups,
    SkillsShSearchState? skillsSh,
    SkillLoadStatus? status,
    String? errorMessage,
    bool clearError = false,
    Set<String>? busyIds,
    bool? discoveryLoading,
    bool? updatesLoading,
    Set<String>? repoSyncingKeys,
  }) => SkillState(
    installed: installed ?? this.installed,
    repos: repos ?? this.repos,
    discoverable: discoverable ?? this.discoverable,
    updates: updates ?? this.updates,
    backups: backups ?? this.backups,
    skillsSh: skillsSh ?? this.skillsSh,
    status: status ?? this.status,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    busyIds: busyIds ?? this.busyIds,
    discoveryLoading: discoveryLoading ?? this.discoveryLoading,
    updatesLoading: updatesLoading ?? this.updatesLoading,
    repoSyncingKeys: repoSyncingKeys ?? this.repoSyncingKeys,
  );

  @override
  List<Object?> get props => [
    installed,
    repos,
    discoverable,
    updates,
    backups,
    skillsSh,
    status,
    errorMessage,
    busyIds,
    discoveryLoading,
    updatesLoading,
    repoSyncingKeys,
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
        _repo.loadBackups(),
      ]);
      final installed = results[0] as List<Skill>;
      final repos = results[1] as List<SkillRepo>;
      final backups = results[2] as List<SkillBackup>;
      emit(
        state.copyWith(
          installed: installed,
          repos: repos,
          backups: backups,
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
    final generation = ++_discoveryGeneration;
    final enabled = state.repos.where((r) => r.enabled).toList();
    if (enabled.isEmpty) {
      if (generation != _discoveryGeneration) return;
      emit(
        state.copyWith(
          discoveryLoading: false,
          discoverable: const [],
          repoSyncingKeys: const {},
        ),
      );
      return;
    }

    var syncing = enabled.map(SkillRepoDiskCacheService.repoKey).toSet();
    emit(
      state.copyWith(
        discoveryLoading: true,
        discoverable: await _aggregateDiscoverableFromDisk(enabled),
        repoSyncingKeys: syncing,
        clearError: true,
      ),
    );

    for (final repo in enabled) {
      if (generation != _discoveryGeneration) return;
      final key = SkillRepoDiskCacheService.repoKey(repo);
      try {
        await _repo.syncRepoCache(repo, force: force);
      } catch (e) {
        appLogger.w('[skills] sync ${repo.fullName} failed: $e');
      }
      if (generation != _discoveryGeneration) return;
      syncing = Set.of(syncing)..remove(key);
      emit(
        state.copyWith(
          discoverable: await _aggregateDiscoverableFromDisk(enabled),
          discoveryLoading: true,
          repoSyncingKeys: syncing,
        ),
      );
    }
    if (generation != _discoveryGeneration) return;
    emit(
      state.copyWith(discoveryLoading: false, repoSyncingKeys: const {}),
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
      unawaited(refreshDiscoverable());
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
      emit(state.copyWith(repos: repos));
      unawaited(refreshDiscoverable());
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    }
  }

  Future<void> toggleRepoEnabled(SkillRepo repo, bool enabled) async {
    try {
      await _repo.repos.setEnabled(repo.owner, repo.name, enabled);
      final repos = await _repo.loadRepos();
      emit(state.copyWith(repos: repos));
      unawaited(refreshDiscoverable());
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
    emit(state.copyWith(clearError: true));
    try {
      await _repo.installFromZip(zip);
      final installed = await _repo.loadInstalled();
      emit(state.copyWith(installed: installed));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
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
    emit(state.copyWith(clearError: true));
    try {
      await _repo.uninstall(s);
      final installed = await _repo.loadInstalled();
      final backups = await _repo.loadBackups();
      emit(state.copyWith(installed: installed, backups: backups));
      await _onSkillUninstalled?.call(s.id);
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
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
      final backups = await _repo.loadBackups();
      final updates = state.updates.where((u) => u.id != s.id).toList();
      emit(
        state.copyWith(
          installed: installed,
          backups: backups,
          updates: updates,
        ),
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    } finally {
      final next = {...state.busyIds}..remove(s.id);
      emit(state.copyWith(busyIds: next));
    }
  }

  Future<void> updateAll() async {
    for (final u in List<SkillUpdateInfo>.from(state.updates)) {
      final match = state.installed.where((s) => s.id == u.id).toList();
      if (match.isEmpty) continue;
      final skill = match.first;
      if (skill.repoOwner == null) continue;
      await updateSkill(skill);
    }
  }

  Future<void> restoreBackup(SkillBackup b) async {
    try {
      await _repo.restoreBackup(b);
      final installed = await _repo.loadInstalled();
      final backups = await _repo.loadBackups();
      emit(state.copyWith(installed: installed, backups: backups));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    }
  }

  Future<void> deleteBackup(SkillBackup b) async {
    try {
      await _repo.deleteBackup(b);
      final backups = await _repo.loadBackups();
      emit(state.copyWith(backups: backups));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
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
    try {
      await _repo.importUnmanaged(sel);
      final installed = await _repo.loadInstalled();
      emit(state.copyWith(installed: installed));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
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
