import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/skill.dart';
import '../repositories/skill_repository.dart';
import '../services/skill_fetch_service.dart';
import '../services/skill_install_service.dart';
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
  ];
}

class SkillCubit extends Cubit<SkillState> {
  SkillCubit(this._repo) : super(const SkillState());

  final SkillRepository _repo;

  Future<void> loadAll() async {
    emit(state.copyWith(status: SkillLoadStatus.loading, clearError: true));
    try {
      final installed = await _repo.loadInstalled();
      final repos = await _repo.loadRepos();
      final backups = await _repo.loadBackups();
      emit(state.copyWith(
        installed: installed,
        repos: repos,
        backups: backups,
        status: SkillLoadStatus.ready,
      ));
      unawaited(refreshDiscoverable());
    } catch (e) {
      appLogger.e('[skills] loadAll failed: $e');
      emit(state.copyWith(
        status: SkillLoadStatus.error,
        errorMessage: '$e',
      ));
    }
  }

  Future<void> refreshDiscoverable() async {
    emit(state.copyWith(discoveryLoading: true));
    try {
      final list = await _repo.discover(state.repos);
      emit(state.copyWith(
        discoverable: list,
        discoveryLoading: false,
        clearError: true,
      ));
    } catch (e) {
      emit(state.copyWith(
        discoveryLoading: false,
        errorMessage: 'Discovery failed: $e',
      ));
    }
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
      emit(state.copyWith(
        updatesLoading: false,
        errorMessage: '$e',
      ));
    }
  }

  Future<void> updateSkill(Skill s) async {
    emit(state.copyWith(
      busyIds: {...state.busyIds, s.id},
      clearError: true,
    ));
    try {
      await _repo.updateSkill(s);
      final installed = await _repo.loadInstalled();
      final backups = await _repo.loadBackups();
      final updates = state.updates.where((u) => u.id != s.id).toList();
      emit(state.copyWith(
        installed: installed,
        backups: backups,
        updates: updates,
      ));
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
    emit(state.copyWith(
      skillsSh: state.skillsSh.copyWith(
        loading: true,
        query: query,
        offset: 0,
        entries: const [],
      ),
      clearError: true,
    ));
    try {
      final res = await _repo.searchSkillsSh(query, offset: 0);
      emit(state.copyWith(
        skillsSh: SkillsShSearchState(
          query: query,
          entries: res.skills,
          totalCount: res.totalCount,
          offset: res.skills.length,
          loading: false,
        ),
      ));
    } catch (e) {
      emit(state.copyWith(
        skillsSh: state.skillsSh.copyWith(loading: false),
        errorMessage: '$e',
      ));
    }
  }

  Future<void> loadMoreSkillsSh() async {
    if (state.skillsSh.loading) return;
    if (state.skillsSh.entries.length >= state.skillsSh.totalCount) return;
    emit(state.copyWith(
      skillsSh: state.skillsSh.copyWith(loading: true),
    ));
    try {
      final res = await _repo.searchSkillsSh(
        state.skillsSh.query,
        offset: state.skillsSh.offset,
      );
      final merged = [...state.skillsSh.entries, ...res.skills];
      emit(state.copyWith(
        skillsSh: state.skillsSh.copyWith(
          entries: merged,
          offset: merged.length,
          totalCount: res.totalCount,
          loading: false,
        ),
      ));
    } catch (e) {
      emit(state.copyWith(
        skillsSh: state.skillsSh.copyWith(loading: false),
        errorMessage: '$e',
      ));
    }
  }

  void clearError() => emit(state.copyWith(clearError: true));
}
