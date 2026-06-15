import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/plugin.dart';
import '../models/project_profile.dart';
import '../models/team_config.dart';
import '../repositories/project_profile_repository.dart';
import '../services/plugin/project_plugin_linker_service.dart';
import '../utils/logger.dart';

typedef InstalledPluginsLoader = Future<List<Plugin>> Function();

enum ProjectProfileLoadStatus { idle, loading, ready, error }

class ProjectProfileState extends Equatable {
  const ProjectProfileState({
    this.projectId,
    this.profile,
    this.status = ProjectProfileLoadStatus.idle,
    this.errorMessage,
    this.isSyncingPlugins = false,
  });

  final String? projectId;
  final ProjectProfile? profile;
  final ProjectProfileLoadStatus status;
  final String? errorMessage;
  final bool isSyncingPlugins;

  ProjectProfileState copyWith({
    String? projectId,
    ProjectProfile? profile,
    ProjectProfileLoadStatus? status,
    String? errorMessage,
    bool clearError = false,
    bool? isSyncingPlugins,
  }) {
    return ProjectProfileState(
      projectId: projectId ?? this.projectId,
      profile: profile ?? this.profile,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isSyncingPlugins: isSyncingPlugins ?? this.isSyncingPlugins,
    );
  }

  @override
  List<Object?> get props => [
    projectId,
    profile,
    status,
    errorMessage,
    isSyncingPlugins,
  ];
}

/// Loads and persists [ProjectProfile] for a personal project and syncs
/// plugin links when the plugin id list changes.
class ProjectProfileCubit extends Cubit<ProjectProfileState> {
  ProjectProfileCubit({
    required ProjectProfileRepository repository,
    required ProjectPluginLinkerService pluginLinker,
    InstalledPluginsLoader? installedPluginsLoader,
  }) : _repository = repository,
       _pluginLinker = pluginLinker,
       _installedPluginsLoader =
           installedPluginsLoader ?? (() => Future.value(const <Plugin>[])),
       super(const ProjectProfileState());

  final ProjectProfileRepository _repository;
  final ProjectPluginLinkerService _pluginLinker;
  final InstalledPluginsLoader _installedPluginsLoader;

  Future<void> load(String projectId, {bool force = false}) async {
    final trimmed = projectId.trim();
    if (trimmed.isEmpty) return;
    if (!force &&
        state.projectId == trimmed &&
        state.status == ProjectProfileLoadStatus.ready) {
      return;
    }

    emit(
      state.copyWith(
        projectId: trimmed,
        status: ProjectProfileLoadStatus.loading,
        clearError: true,
      ),
    );
    try {
      final profile = await _repository.loadOrCreate(trimmed);
      emit(
        state.copyWith(
          profile: profile,
          status: ProjectProfileLoadStatus.ready,
        ),
      );
      if (profile.pluginIds.isNotEmpty) {
        await _syncPlugins(profile);
      }
    } on Object catch (e) {
      appLogger.e('[project-profile] load failed: $e');
      emit(
        state.copyWith(
          status: ProjectProfileLoadStatus.error,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> updateAgent(ProjectAgentConfig agent) async {
    final profile = state.profile;
    if (profile == null) return;
    await _persist(profile.copyWith(agent: agent));
  }

  // TODO: migrate to presets — removed in CLI presets migration
  // ignore: avoid-unused-parameters
  Future<void> setCli(CliTool cli) async {
    // Stub — CLI selection is now handled via activePresetId
  }

  // TODO: migrate to presets — removed in CLI presets migration
  // ignore: avoid-unused-parameters
  Future<void> setCliDefaults(
    CliTool cli, {
    required String provider,
    required String model,
    String effort = '',
  }) async {
    // Stub — CLI defaults are now configured via CliPresetsCubit
  }

  Future<void> setMcpServerIds(List<String> mcpServerIds) async {
    final profile = state.profile;
    if (profile == null) return;
    await _persist(
      profile.copyWith(
        mcpServerIds: List<String>.unmodifiable(mcpServerIds),
      ),
    );
  }

  Future<void> setSkillIds(List<String> skillIds) async {
    final profile = state.profile;
    if (profile == null) return;
    await _persist(
      profile.copyWith(skillIds: List<String>.unmodifiable(skillIds)),
    );
  }

  Future<void> setPluginIds(List<String> pluginIds) async {
    final profile = state.profile;
    if (profile == null) return;
    final next = profile.copyWith(
      pluginIds: List<String>.unmodifiable(pluginIds),
    );
    await _persist(next);
    await _syncPlugins(next);
  }

  Future<void> _persist(ProjectProfile profile) async {
    final stamped = profile.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _repository.save(stamped);
    emit(state.copyWith(profile: stamped));
  }

  Future<void> _syncPlugins(ProjectProfile profile) async {
    emit(state.copyWith(isSyncingPlugins: true));
    try {
      final catalog = await _installedPluginsLoader();
      var result = await _pluginLinker.syncForProject(
        projectId: profile.projectId,
        pluginIds: profile.pluginIds,
        installed: catalog,
      );

      if (result.skippedMissingIds.isNotEmpty) {
        final prunedIds = profile.pluginIds
            .where((id) => !result.skippedMissingIds.contains(id))
            .toList(growable: false);
        if (prunedIds.length != profile.pluginIds.length) {
          final pruned = profile.copyWith(pluginIds: prunedIds);
          await _persist(pruned);
          result = await _pluginLinker.syncForProject(
            projectId: profile.projectId,
            pluginIds: prunedIds,
            installed: catalog,
          );
        }
      }

      if (result.errors.isNotEmpty) {
        appLogger.w('[project-plugins] sync errors: ${result.errors}');
      }
    } catch (e) {
      appLogger.e('[project-plugins] sync failed: $e');
    } finally {
      emit(state.copyWith(isSyncingPlugins: false));
    }
  }
}
