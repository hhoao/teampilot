import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/mcp_server.dart';
import '../models/plugin.dart';
import '../models/team_config.dart';
import '../repositories/mcp_repository.dart';
import '../repositories/plugin_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/team_repository.dart';
import '../services/cli/registry/cli_tool_registry.dart';
import '../services/team/default_team_project_service.dart';
import '../services/provider/config_profile_service.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/mcp/team_mcp_linker_service.dart';
import '../services/plugin/team_plugin_linker_service.dart';
import '../utils/logger.dart';
import '../utils/team_member_naming.dart';
import 'team/model/team_state.dart';
import 'team/team_cubit_host.dart';
import 'team/team_launch_service.dart';
import 'team/team_profile_provisioner.dart';
import 'team/team_resource_sync_service.dart';
import 'team/team_roster_editor.dart';

export 'team/model/team_state.dart';
export 'team/team_launch_service.dart' show TeamLauncher, CliExecutableResolver;
export 'team/team_resource_sync_service.dart'
    show mergeExtensionMcp, InstalledPluginsLoader, InstalledMcpLoader;

/// Owns team/member roster state and coordinates resource linking
/// ([TeamResourceSyncService]), launching ([TeamLaunchService]) and
/// config-profile provisioning ([TeamProfileProvisioner]). Roster transforms
/// live in [TeamRosterEditor]; this cubit persists and emits.
class TeamCubit extends Cubit<TeamState> implements TeamCubitHost {
  TeamCubit({
    required TeamRepository repository,
    required SessionRepository sessionRepository,
    required Future<void> Function() reloadProjects,
    required String Function() executableResolver,
    CliExecutableResolver? cliExecutableResolver,
    TeamLauncher? launcher,
    String? Function()? llmConfigPathOverride,
    String appDataBasePath = '',
    ConfigProfileService? configProfileService,
    StorageRootsResolver? storageRootsResolver,
    SessionLifecycleService? lifecycleService,
    TeamPluginLinkerService? pluginLinker,
    PluginRepository? pluginRepository,
    InstalledPluginsLoader? installedPluginsLoader,
    TeamMcpLinkerService? mcpLinker,
    McpRepository? mcpRepository,
    InstalledMcpLoader? installedMcpLoader,
    Future<List<McpServer>> Function(String teamId)? extensionMcpContributor,
  }) : _repository = repository,
       _sessionRepository = sessionRepository,
       _reloadProjects = reloadProjects,
       _executableResolver = executableResolver,
       _cliExecutableResolver = cliExecutableResolver,
       _appDataBasePath = appDataBasePath,
       _configProfileService = configProfileService,
       _storageRootsResolver = storageRootsResolver,
       _lifecycle =
           lifecycleService ??
           SessionLifecycleService(
             appDataBasePath: appDataBasePath.isNotEmpty
                 ? appDataBasePath
                 : null,
             llmConfigPathOverride: llmConfigPathOverride,
             configProfileService: configProfileService,
             storageRootsResolver: storageRootsResolver,
           ),
       _pluginLinker = pluginLinker ?? TeamPluginLinkerService(),
       _pluginRepository = pluginRepository ?? PluginRepository(),
       _installedPluginsLoader = installedPluginsLoader,
       _mcpLinker = mcpLinker ?? TeamMcpLinkerService(),
       _mcpRepository = mcpRepository ?? McpRepository(),
       _installedMcpLoader = installedMcpLoader,
       _extensionMcpContributor = extensionMcpContributor ?? _noExtensionMcp,
       _launcher = launcher,
       super(const TeamState());

  static Future<List<McpServer>> _noExtensionMcp(String teamId) async =>
      const <McpServer>[];

  final TeamRepository _repository;
  final SessionRepository _sessionRepository;
  final Future<void> Function() _reloadProjects;
  final String Function() _executableResolver;
  final CliExecutableResolver? _cliExecutableResolver;
  final String _appDataBasePath;
  final ConfigProfileService? _configProfileService;
  final StorageRootsResolver? _storageRootsResolver;
  final SessionLifecycleService _lifecycle;
  final TeamPluginLinkerService _pluginLinker;
  final PluginRepository _pluginRepository;
  final InstalledPluginsLoader? _installedPluginsLoader;
  final TeamMcpLinkerService _mcpLinker;
  final McpRepository _mcpRepository;
  final InstalledMcpLoader? _installedMcpLoader;
  final Future<List<McpServer>> Function(String teamId) _extensionMcpContributor;
  final TeamLauncher? _launcher;

  final TeamRosterEditor _rosterEditor = const TeamRosterEditor();

  late final TeamProfileProvisioner _provisioner = TeamProfileProvisioner(
    configProfileService: _configProfileService,
    storageRootsResolver: _storageRootsResolver,
    appDataBasePathOverride: _appDataBasePath,
  );

  late final TeamResourceSyncService _sync = TeamResourceSyncService(
    host: this,
    provisioner: _provisioner,
    pluginLinker: _pluginLinker,
    mcpLinker: _mcpLinker,
    pluginRepository: _pluginRepository,
    mcpRepository: _mcpRepository,
    installedPluginsLoader: _installedPluginsLoader,
    installedMcpLoader: _installedMcpLoader,
    extensionMcpContributor: _extensionMcpContributor,
  );

  late final TeamLaunchService _launchService = TeamLaunchService(
    host: this,
    lifecycle: _lifecycle,
    sync: _sync,
    executableResolver: _executableResolver,
    cliExecutableResolver: _cliExecutableResolver,
    launcher: _launcher,
  );

  // ===== TeamCubitHost =====

  @override
  void applyState(TeamState next) {
    if (!isClosed) emit(next);
  }

  @override
  Future<void> saveTeams(List<TeamConfig> teams) => _repository.saveTeams(teams);

  // ===== Launch / preview (delegated) =====

  String previewFor(TeamMemberConfig member) =>
      _launchService.previewFor(member);

  String get selectedCommandPreview => _launchService.selectedCommandPreview;

  Future<void> launchMember(String memberId) =>
      _launchService.launchMember(memberId);

  Future<void> launchSelectedTeam() => _launchService.launchSelectedTeam();

  // ===== Resource sync (delegated) =====

  Future<void> syncSelectedTeamPlugins({List<Plugin>? installed}) =>
      _sync.syncPluginsForSelected(installed: installed);

  Future<void> syncSelectedTeamMcp({List<McpServer>? installed}) =>
      _sync.syncMcp(installed: installed);

  Future<void> syncTeamsUsingPlugin(
    String pluginId, {
    List<Plugin>? installed,
  }) => _sync.syncTeamsUsingPlugin(pluginId, installed: installed);

  Future<void> removeMcpFromAllTeams(String mcpId) =>
      _sync.removeMcpFromAllTeams(mcpId);

  Future<void> removeSkillFromAllTeams(String skillId) =>
      _sync.removeSkillFromAllTeams(skillId);

  Future<void> removePluginFromAllTeams(String pluginId) =>
      _sync.removePluginFromAllTeams(pluginId);

  // ===== Team lifecycle =====

  Future<void> load({bool awaitProfiles = false}) async {
    appLogger.i('TeamCubit loading teams...');
    emit(state.copyWith(isLoading: true));
    var teams = await _repository.loadTeams();
    if (teams.isEmpty) {
      final team = _rosterEditor.defaultTeam();
      teams = [team];
      await _repository.saveTeams(teams);
      await _seedDefaultProject(team);
    }
    emit(
      state.copyWith(
        teams: teams,
        selectedTeamId: teams.first.id,
        isLoading: false,
        statusMessage: 'Ready.',
      ),
    );
    appLogger.i('TeamCubit loaded ${teams.length} teams');
    final profiles = _provisioner.ensureForTeams(teams);
    if (awaitProfiles) {
      await profiles;
    } else {
      unawaited(
        profiles.catchError((Object e) {
          appLogger.w('[TeamCubit] background profile ensure failed: $e');
        }),
      );
    }
  }

  Future<void> reorderTeams(int oldIndex, int newIndex) async {
    final teams = state.teams;
    if (oldIndex < 0 || oldIndex >= teams.length) return;
    var targetIndex = newIndex;
    if (targetIndex < 0 || targetIndex > teams.length) return;
    if (targetIndex > oldIndex) targetIndex -= 1;
    if (oldIndex == targetIndex) return;

    final reordered = List<TeamConfig>.of(teams);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(targetIndex, moved);
    final stamped = [
      for (var i = 0; i < reordered.length; i++)
        reordered[i].copyWith(sortOrder: i + 1),
    ];
    emit(state.copyWith(teams: stamped));
    await _repository.saveTeams(stamped);
  }

  Future<void> selectTeam(String id) async {
    if (!state.teams.any((team) => team.id == id)) return;
    final team = state.teams.firstWhere((t) => t.id == id);
    emit(
      state.copyWith(
        selectedTeamId: id,
        statusMessage: 'Selected ${team.name}.',
      ),
    );
    await Future.wait([
      _sync.syncPluginsForSelected(),
      _sync.syncMcp(),
    ]);
  }

  Future<bool> addTeam(
    String name, {
    CliTool cli = CliTool.claude,
    TeamMode teamMode = TeamMode.native,
    Map<String, String> providerIdsByTool = const {},
    List<TeamMemberConfig>? members,
    String description = '',
    List<String> skillIds = const [],
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      emit(state.copyWith(statusMessage: 'Team name is required.'));
      return false;
    }
    if (state.teams.any((t) => t.name == trimmed)) {
      emit(state.copyWith(statusMessage: 'Team "$trimmed" already exists.'));
      return false;
    }
    if (!_teamCliAllowed(cli: cli, teamMode: teamMode)) {
      emit(
        state.copyWith(
          statusMessage: teamMode == TeamMode.native
              ? 'CLI "${cli.value}" does not support native team mode.'
              : 'CLI "${cli.value}" is not available for teams yet.',
        ),
      );
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final teamId = TeamMemberNaming.uniqueTeamId(
      trimmed,
      state.teams.map((t) => t.id),
    );
    final team = TeamConfig(
      id: teamId,
      name: trimmed,
      description: description.trim(),
      cli: cli,
      teamMode: teamMode,
      providerIdsByTool: providerIdsByTool,
      skillIds: skillIds,
      createdAt: now,
      members: members ?? TeamMemberNaming.defaultRoster(joinedAt: now),
    );
    final teams = [...state.teams, team];
    emit(
      state.copyWith(
        teams: teams,
        selectedTeamId: team.id,
        statusMessage: 'Added ${team.name}.',
      ),
    );
    await _repository.saveTeams(teams);
    await _provisioner.ensureTeamProfile(team.id, cli: team.cli);
    await _seedDefaultProject(team);
    unawaited(_sync.syncPluginsForSelected());
    return true;
  }

  /// Creates a team cloned from a TeamHub template. Unlike [addTeam], a
  /// colliding display name is auto-suffixed (clone must never fail on a name
  /// clash) and skill/plugin/MCP ids are carried over.
  Future<String?> addClonedTeam({
    required String name,
    required CliTool cli,
    TeamMode teamMode = TeamMode.native,
    required List<TeamMemberConfig> members,
    List<String> skillIds = const [],
    List<String> pluginIds = const [],
    List<String> mcpServerIds = const [],
    String description = '',
    String extraArgs = '',
  }) async {
    final base = name.trim().isEmpty ? 'Team' : name.trim();
    if (!_teamCliAllowed(cli: cli, teamMode: teamMode)) {
      emit(
        state.copyWith(
          statusMessage: teamMode == TeamMode.native
              ? 'CLI "${cli.value}" does not support native team mode.'
              : 'CLI "${cli.value}" is not available for teams yet.',
        ),
      );
      return null;
    }
    final displayName = _rosterEditor.uniqueDisplayName(
      base,
      state.teams.map((t) => t.name).toSet(),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final teamId = TeamMemberNaming.uniqueTeamId(
      displayName,
      state.teams.map((t) => t.id),
    );
    final roster = members.isEmpty
        ? TeamMemberNaming.defaultRoster(joinedAt: now)
        : members;
    final team = TeamConfig(
      id: teamId,
      name: displayName,
      description: description,
      extraArgs: extraArgs,
      cli: cli,
      teamMode: teamMode,
      createdAt: now,
      members: roster,
      skillIds: skillIds,
      pluginIds: pluginIds,
      mcpServerIds: mcpServerIds,
    );
    final teams = [...state.teams, team];
    emit(
      state.copyWith(
        teams: teams,
        selectedTeamId: team.id,
        statusMessage: 'Cloned ${team.name}.',
      ),
    );
    await _repository.saveTeams(teams);
    await _provisioner.ensureTeamProfile(team.id, cli: team.cli);
    await _seedDefaultProject(team);
    unawaited(_sync.syncPluginsForSelected());
    return team.id;
  }

  Future<void> _seedDefaultProject(TeamConfig team) async {
    await DefaultTeamProjectService.seed(_sessionRepository, team);
    await _reloadProjects();
  }

  /// Renames the selected team and removes persisted files keyed by the old name.
  Future<bool> renameSelectedTeamName(String newName) async {
    final selected = state.selectedTeam;
    if (selected == null) return false;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      emit(state.copyWith(statusMessage: 'Team name is required.'));
      return false;
    }
    if (trimmed == selected.name) return true;
    if (state.teams.any((t) => t.name == trimmed && t.id != selected.id)) {
      emit(state.copyWith(statusMessage: 'Team "$trimmed" already exists.'));
      return false;
    }
    final oldName = selected.name;
    final updated = selected.copyWith(name: trimmed);
    final teams = [
      for (final team in state.teams)
        if (team.id == selected.id) updated else team,
    ];
    emit(
      state.copyWith(
        teams: teams,
        selectedTeamId: selected.id,
        statusMessage: 'Renamed team to $trimmed.',
      ),
    );
    await _repository.saveTeams(teams);
    if (oldName != trimmed) {
      await _repository.deleteTeam(oldName, destroyCliState: false);
    }
    return true;
  }

  /// Sets [providerIdsByTool]['claude'] on Claude teams that do not already
  /// have a team-level provider binding.
  Future<void> bindClaudeProviderForTeamsWithoutBinding(
    String providerId,
  ) async {
    final trimmed = providerId.trim();
    if (trimmed.isEmpty) return;

    var changed = false;
    final teams = <TeamConfig>[];
    for (final team in state.teams) {
      if (team.cli != CliTool.claude) {
        teams.add(team);
        continue;
      }
      final existing = team.providerIdsByTool['claude']?.trim() ?? '';
      if (existing.isNotEmpty) {
        teams.add(team);
        continue;
      }
      changed = true;
      teams.add(
        team.copyWith(
          providerIdsByTool: {...team.providerIdsByTool, 'claude': trimmed},
        ),
      );
    }
    if (!changed) return;

    emit(state.copyWith(teams: teams));
    await _repository.saveTeams(teams);
  }

  Future<void> updateSelected(TeamConfig updated) async {
    final selected = state.selectedTeam;
    if (selected == null) return;
    final pluginsChanged = !listEquals(selected.pluginIds, updated.pluginIds);
    final mcpChanged = !listEquals(selected.mcpServerIds, updated.mcpServerIds);
    final normalized = _rosterEditor.normalizeTeam(
      updated.members.isEmpty
          ? updated.copyWith(members: TeamMemberNaming.defaultRoster())
          : updated,
    );
    final teams = [
      for (final team in state.teams)
        if (team.id == selected.id) normalized else team,
    ];
    emit(
      state.copyWith(
        teams: teams,
        selectedTeamId: normalized.id,
        statusMessage: normalized.isValid
            ? 'Saved ${normalized.name}.'
            : 'Name is required.',
      ),
    );
    await _repository.saveTeams(teams);
    if (pluginsChanged) {
      await _sync.syncPluginsForSelected();
    }
    if (mcpChanged) {
      await _sync.syncMcp();
    }
  }

  Future<void> deleteSelected() async {
    final selected = state.selectedTeam;
    if (selected == null) return;
    final teamId = selected.id;
    for (final project in await _sessionRepository.loadProjects()) {
      if (project.teamId == teamId) {
        await _sessionRepository.deleteProject(project.projectId);
      }
    }
    await _repository.deleteTeam(selected.name, cliStateTeamId: selected.id);
    var teams = state.teams.where((team) => team.id != selected.id).toList();
    if (teams.isEmpty) teams = [_rosterEditor.defaultTeam()];
    emit(
      state.copyWith(
        teams: teams,
        selectedTeamId: teams.first.id,
        statusMessage: 'Deleted ${selected.name}.',
      ),
    );
    await _repository.saveTeams(teams);
    unawaited(_sync.syncPluginsForSelected());
  }

  // ===== Members =====

  Future<void> addMember() async {
    final team = state.selectedTeam;
    if (team == null) return;
    final (team: updated, :added) = _rosterEditor.addMember(team);
    await updateSelected(updated);
    emit(state.copyWith(statusMessage: 'Added ${added.name}.'));
  }

  Future<void> updateMember(String memberId, TeamMemberConfig updated) async {
    final team = state.selectedTeam;
    if (team == null) return;
    final mutation = _rosterEditor.updateMember(team, memberId, updated);
    if (mutation.isRejected) {
      emit(state.copyWith(statusMessage: mutation.statusMessage));
      return;
    }
    await updateSelected(mutation.team!);
  }

  Future<void> deleteMember(String memberId) async {
    final team = state.selectedTeam;
    if (team == null) return;
    final mutation = _rosterEditor.removeMember(team, memberId);
    if (mutation.isRejected) {
      emit(state.copyWith(statusMessage: mutation.statusMessage));
      return;
    }
    await updateSelected(mutation.team!);
    emit(state.copyWith(statusMessage: mutation.statusMessage));
  }

  /// Updates [TeamMemberConfig.provider] on every team when an LLM provider is renamed.
  Future<void> renameLlmProviderReference(String from, String to) async {
    if (from == to) return;
    var changed = false;
    final teams = <TeamConfig>[];
    for (final team in state.teams) {
      var teamChanged = false;
      final members = <TeamMemberConfig>[];
      for (final m in team.members) {
        if (m.provider == from) {
          teamChanged = true;
          changed = true;
          members.add(m.copyWith(provider: to));
        } else {
          members.add(m);
        }
      }
      teams.add(teamChanged ? team.copyWith(members: members) : team);
    }
    if (!changed) return;
    emit(state.copyWith(teams: teams));
    await _repository.saveTeams(teams);
  }

  bool _teamCliAllowed({required CliTool cli, required TeamMode teamMode}) {
    final registry = CliToolRegistry.builtIn();
    final def = registry.tryGet(cli);
    if (def == null || !def.isLaunchSupported) return false;
    if (teamMode == TeamMode.native && !registry.supportsNativeTeam(cli)) {
      return false;
    }
    return true;
  }
}
