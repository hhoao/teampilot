import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/mcp_server.dart';
import '../models/personal_identity.dart';
import '../models/plugin.dart';
import '../models/team_config.dart';
import '../models/identity.dart';
import '../repositories/mcp_repository.dart';
import '../repositories/plugin_repository.dart';
import '../repositories/identity_repository.dart';
import '../repositories/session_repository.dart';
import '../services/cli/registry/cli_tool_registry.dart';
import '../services/team/default_team_workspace_service.dart';
import '../services/provider/config_profile_service.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/mcp/identity_mcp_linker_service.dart';
import '../services/storage/identity_provisioner.dart';
import '../services/plugin/identity_plugin_linker_service.dart';
import '../utils/logger.dart';
import '../utils/team_member_naming.dart';
import 'team/identity_cubit_host.dart';
import 'team/model/identity_state.dart';
import 'team/team_launch_service.dart';
import 'team/team_profile_provisioner.dart';
import 'team/team_resource_sync_service.dart';
import 'team/team_roster_editor.dart';

export 'team/model/identity_state.dart';
export 'team/team_launch_service.dart' show TeamLauncher, CliExecutableResolver;
export 'team/team_resource_sync_service.dart'
    show mergeExtensionMcp, InstalledPluginsLoader, InstalledMcpLoader;

/// Owns workspace identity state (personal + team) and coordinates resource
/// linking ([TeamResourceSyncService]), launching ([TeamLaunchService]) and
/// config-profile provisioning ([TeamProfileProvisioner]). Roster transforms
/// live in [TeamRosterEditor]; this cubit persists and emits.
class IdentityCubit extends Cubit<IdentityState> implements IdentityCubitHost {
  IdentityCubit({
    required IdentityRepository repository,
    required SessionRepository sessionRepository,
    required Future<void> Function() reloadWorkspaces,
    required String Function() executableResolver,
    CliExecutableResolver? cliExecutableResolver,
    TeamLauncher? launcher,
    String? Function()? llmConfigPathOverride,
    String appDataBasePath = '',
    ConfigProfileService? configProfileService,
    StorageRootsResolver? storageRootsResolver,
    SessionLifecycleService? lifecycleService,
    IdentityPluginLinkerService? pluginLinker,
    PluginRepository? pluginRepository,
    InstalledPluginsLoader? installedPluginsLoader,
    IdentityMcpLinkerService? mcpLinker,
    McpRepository? mcpRepository,
    InstalledMcpLoader? installedMcpLoader,
    Future<List<McpServer>> Function(String teamId)? extensionMcpContributor,
  }) : _repository = repository,
       _sessionRepository = sessionRepository,
       _reloadWorkspaces = reloadWorkspaces,
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
       _pluginLinker = pluginLinker ?? IdentityPluginLinkerService(),
       _pluginRepository = pluginRepository ?? PluginRepository(),
       _installedPluginsLoader = installedPluginsLoader,
       _mcpLinker = mcpLinker ?? IdentityMcpLinkerService(),
       _mcpRepository = mcpRepository ?? McpRepository(),
       _installedMcpLoader = installedMcpLoader,
       _extensionMcpContributor = extensionMcpContributor ?? _noExtensionMcp,
       _launcher = launcher,
       super(const IdentityState());

  static Future<List<McpServer>> _noExtensionMcp(String teamId) async =>
      const <McpServer>[];

  final IdentityRepository _repository;
  final SessionRepository _sessionRepository;
  final Future<void> Function() _reloadWorkspaces;
  final String Function() _executableResolver;
  final CliExecutableResolver? _cliExecutableResolver;
  final String _appDataBasePath;
  final ConfigProfileService? _configProfileService;
  final StorageRootsResolver? _storageRootsResolver;
  final SessionLifecycleService _lifecycle;
  final IdentityPluginLinkerService _pluginLinker;
  final PluginRepository _pluginRepository;
  final InstalledPluginsLoader? _installedPluginsLoader;
  final IdentityMcpLinkerService _mcpLinker;
  final McpRepository _mcpRepository;
  final InstalledMcpLoader? _installedMcpLoader;
  final Future<List<McpServer>> Function(String teamId)
  _extensionMcpContributor;
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

  // ===== IdentityCubitHost =====

  @override
  void applyState(IdentityState next) {
    if (!isClosed) emit(next);
  }

  @override
  Future<void> saveTeams(List<TeamIdentity> teams) async {
    for (final team in teams) {
      await _repository.save(team);
    }
  }

  Identity? byId(String id) => state.byId(id);

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

  Future<void> removeMcpFromAllTeams(String mcpId) async {
    await _sync.removeMcpFromAllTeams(mcpId);
    await _pruneMcpFromPersonals(mcpId);
  }

  Future<void> removeSkillFromAllTeams(String skillId) async {
    await _sync.removeSkillFromAllTeams(skillId);
    await _pruneSkillFromPersonals(skillId);
  }

  Future<void> removePluginFromAllTeams(String pluginId) async {
    await _sync.removePluginFromAllTeams(pluginId);
    await _prunePluginFromPersonals(pluginId);
  }

  // ===== Personal identities =====

  Future<void> savePersonal(PersonalIdentity identity) async {
    await _repository.save(identity);
    await _reloadIdentities();
    // Every save path (skills/mcp/agent/preset and plugins) goes through here,
    // so relink plugins on save to keep the runtime bundle in sync — the
    // section widgets call savePersonal directly rather than per-field setters.
    await _syncPersonalPlugins(identity);
  }

  Future<void> deletePersonal(String id) async {
    if (state.personals.length <= 1) return;
    await _repository.delete(id);
    await _reloadIdentities();
  }

  Future<bool> addPersonal(String display) async {
    final trimmed = display.trim();
    if (trimmed.isEmpty) {
      emit(state.copyWith(statusMessage: 'Workspace name is required.'));
      return false;
    }
    if (state.personals.any((p) => p.display == trimmed) ||
        state.teams.any((t) => t.name == trimmed)) {
      emit(state.copyWith(statusMessage: 'Workspace "$trimmed" already exists.'));
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = TeamMemberNaming.uniqueTeamId(
      trimmed,
      state.identities.map((identity) => identity.id),
    );
    await savePersonal(
      PersonalIdentity(
        id: id,
        display: trimmed,
        createdAt: now,
        sortOrder: state.personals.length + 1,
      ),
    );
    emit(state.copyWith(statusMessage: 'Added $trimmed.'));
    return true;
  }

  Future<void> _reloadIdentities() async {
    final all = await _repository.loadAll();
    final teams = _sortTeams(all.whereType<TeamIdentity>().toList());
    final personals = _sortPersonals(all.whereType<PersonalIdentity>().toList());
    emit(state.copyWith(identities: [...personals, ...teams]));
  }

  List<PersonalIdentity> _sortPersonals(List<PersonalIdentity> personals) {
    final hasCustomOrder = personals.any((personal) => personal.sortOrder > 0);
    final sorted = List<PersonalIdentity>.of(personals);
    sorted.sort((a, b) {
      if (hasCustomOrder) {
        final order = a.sortOrder.compareTo(b.sortOrder);
        if (order != 0) return order;
      }
      if (a.createdAt != b.createdAt) {
        return a.createdAt.compareTo(b.createdAt);
      }
      return a.display.toLowerCase().compareTo(b.display.toLowerCase());
    });
    return sorted;
  }

  List<TeamIdentity> _sortTeams(List<TeamIdentity> teams) {
    final hasCustomOrder = teams.any((team) => team.sortOrder > 0);
    final sorted = List<TeamIdentity>.of(teams);
    sorted.sort((a, b) {
      if (hasCustomOrder) {
        final order = a.sortOrder.compareTo(b.sortOrder);
        if (order != 0) return order;
      }
      if (a.createdAt != b.createdAt) {
        return a.createdAt.compareTo(b.createdAt);
      }
      return a.name.compareTo(b.name);
    });
    return sorted;
  }

  Future<void> _pruneSkillFromPersonals(String skillId) async {
    var changed = false;
    final next = <Identity>[];
    for (final identity in state.identities) {
      if (identity is PersonalIdentity &&
          identity.bundle.skillIds.contains(skillId)) {
        changed = true;
        final pruned = identity.copyWith(
          bundle: identity.bundle.copyWith(
            skillIds: identity.bundle.skillIds
                .where((id) => id != skillId)
                .toList(growable: false),
          ),
        );
        await _repository.save(pruned);
        next.add(pruned);
      } else {
        next.add(identity);
      }
    }
    if (changed) emit(state.copyWith(identities: next));
  }

  Future<void> _prunePluginFromPersonals(String pluginId) async {
    var changed = false;
    final next = <Identity>[];
    for (final identity in state.identities) {
      if (identity is PersonalIdentity &&
          identity.bundle.pluginIds.contains(pluginId)) {
        changed = true;
        final pruned = identity.copyWith(
          bundle: identity.bundle.copyWith(
            pluginIds: identity.bundle.pluginIds
                .where((id) => id != pluginId)
                .toList(growable: false),
          ),
        );
        await _repository.save(pruned);
        next.add(pruned);
      } else {
        next.add(identity);
      }
    }
    if (changed) emit(state.copyWith(identities: next));
  }

  Future<void> _pruneMcpFromPersonals(String mcpId) async {
    var changed = false;
    final next = <Identity>[];
    for (final identity in state.identities) {
      if (identity is PersonalIdentity &&
          identity.bundle.mcpServerIds.contains(mcpId)) {
        changed = true;
        final pruned = identity.copyWith(
          bundle: identity.bundle.copyWith(
            mcpServerIds: identity.bundle.mcpServerIds
                .where((id) => id != mcpId)
                .toList(growable: false),
          ),
        );
        await _repository.save(pruned);
        next.add(pruned);
      } else {
        next.add(identity);
      }
    }
    if (changed) emit(state.copyWith(identities: next));
  }

  // ===== Team lifecycle =====

  Future<void> load({bool awaitProfiles = false}) async {
    appLogger.i('IdentityCubit loading identities...');
    emit(state.copyWith(isLoading: true));
    final all = await _repository.loadAll();
    var teams = _sortTeams(all.whereType<TeamIdentity>().toList());
    final personals = _sortPersonals(all.whereType<PersonalIdentity>().toList());
    if (teams.isEmpty) {
      final team = _rosterEditor.defaultTeam();
      teams = [team];
      await _repository.save(team);
      await _seedDefaultWorkspace(team);
    }
    final selectedId = state.selectedTeamId;
    final nextSelected = selectedId != null &&
            teams.any((team) => team.id == selectedId)
        ? selectedId
        : teams.first.id;
    emit(
      state.copyWith(
        identities: [...personals, ...teams],
        selectedTeamId: nextSelected,
        isLoading: false,
        statusMessage: 'Ready.',
      ),
    );
    appLogger.i(
      'IdentityCubit loaded ${teams.length} teams, ${personals.length} personals',
    );
    final profiles = _provisioner.ensureForTeams(teams);
    if (awaitProfiles) {
      await profiles;
    } else {
      unawaited(
        profiles.catchError((Object e) {
          appLogger.w('[IdentityCubit] background profile ensure failed: $e');
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

    final reordered = List<TeamIdentity>.of(teams);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(targetIndex, moved);
    final stamped = [
      for (var i = 0; i < reordered.length; i++)
        reordered[i].copyWith(sortOrder: i + 1),
    ];
    emit(state.copyWith(teams: stamped));
    await saveTeams(stamped);
  }

  Future<void> reorderPersonals(int oldIndex, int newIndex) async {
    final personals = state.personals;
    if (oldIndex < 0 || oldIndex >= personals.length) return;
    var targetIndex = newIndex;
    if (targetIndex < 0 || targetIndex > personals.length) return;
    if (targetIndex > oldIndex) targetIndex -= 1;
    if (oldIndex == targetIndex) return;

    final reordered = List<PersonalIdentity>.of(personals);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(targetIndex, moved);
    final stamped = [
      for (var i = 0; i < reordered.length; i++)
        reordered[i].copyWith(sortOrder: i + 1),
    ];
    emit(state.copyWith(personals: stamped));
    await savePersonals(stamped);
  }

  Future<void> savePersonals(List<PersonalIdentity> personals) async {
    for (final personal in personals) {
      await _repository.save(personal);
    }
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
    await Future.wait([_sync.syncPluginsForSelected(), _sync.syncMcp()]);
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
    final team = TeamIdentity(
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
    await saveTeams(teams);
    await _provisioner.ensureTeamProfile(team.id, cli: team.cli);
    await _seedDefaultWorkspace(team);
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
    final team = TeamIdentity(
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
    await saveTeams(teams);
    await _provisioner.ensureTeamProfile(team.id, cli: team.cli);
    await _seedDefaultWorkspace(team);
    unawaited(_sync.syncPluginsForSelected());
    return team.id;
  }

  Future<void> _seedDefaultWorkspace(TeamIdentity team) async {
    await DefaultTeamWorkspaceService.seed(_sessionRepository, team);
    await _reloadWorkspaces();
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
    await saveTeams(teams);
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
    final teams = <TeamIdentity>[];
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
    await saveTeams(teams);
  }

  Future<void> updateSelected(TeamIdentity updated) async {
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
    await saveTeams(teams);
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
    for (final session in await _sessionRepository.loadSessions()) {
      if (session.sessionTeam.trim() == teamId) {
        await _sessionRepository.deleteSession(session.sessionId);
      }
    }
    await _repository.delete(teamId);
    var teams = state.teams.where((team) => team.id != selected.id).toList();
    if (teams.isEmpty) teams = [_rosterEditor.defaultTeam()];
    emit(
      state.copyWith(
        teams: teams,
        selectedTeamId: teams.first.id,
        statusMessage: 'Deleted ${selected.name}.',
      ),
    );
    await saveTeams(teams);
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

  /// Sets the active preset for the selected team.
  ///
  /// [presetId] may be a preset UUID, `null` (clear), or empty (clear).
  void setTeamActivePreset(String? presetId) {
    final team = state.selectedTeam;
    if (team == null) return;
    final effectiveId = (presetId == null || presetId.trim().isEmpty)
        ? null
        : presetId.trim();
    updateSelected(
      team.copyWith(activePresetId: effectiveId, updateActivePresetId: true),
    );
  }

  /// Persists team custom launch defaults for [catalogCli] and clears any preset.
  void updateTeamCustomLaunch({
    required CliTool catalogCli,
    CliTool? defaultCli,
    required String providerId,
    required String model,
    required String effort,
  }) {
    final team = state.selectedTeam;
    if (team == null) return;
    var next = team
        .copyWith(activePresetId: null, updateActivePresetId: true)
        .withLaunchDefaultsForCli(
          cli: catalogCli,
          providerId: providerId,
          model: model,
          effort: effort,
        );
    if (defaultCli != null && team.teamMode == TeamMode.mixed) {
      next = next.copyWith(cli: defaultCli);
    }
    updateSelected(next);
  }

  /// Sets the active preset for a member of the selected team.
  ///
  /// [presetId] may be a preset UUID ([CliPreset.id]),
  /// [TeamIdentity.inheritPresetId] to inherit the team default, `null` (clear),
  /// or empty (clear).
  ///
  /// In [TeamMode.mixed], pass [syncCli] when selecting an explicit preset so
  /// the member's CLI matches the preset (launch uses [TeamMemberConfig.cli]).
  Future<void> setMemberActivePreset(
    String memberId,
    String? presetId, {
    CliTool? syncCli,
  }) async {
    final team = state.selectedTeam;
    if (team == null) return;
    final member = team.members.cast<TeamMemberConfig?>().firstWhere(
      (m) => m!.id == memberId,
      orElse: () => null,
    );
    if (member == null) return;
    final effectiveId = (presetId == null || presetId.trim().isEmpty)
        ? null
        : presetId.trim();
    final syncCliFromPreset = team.teamMode == TeamMode.mixed &&
        effectiveId != null &&
        effectiveId != TeamIdentity.inheritPresetId &&
        syncCli != null;
    await updateMember(
      memberId,
      member.copyWith(
        activePresetId: effectiveId,
        updateActivePresetId: true,
        cli: syncCliFromPreset ? syncCli : member.cli,
        updateCli: syncCliFromPreset,
      ),
    );
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
    final teams = <TeamIdentity>[];
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
    await saveTeams(teams);
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

  /// Default personal identity for simple-mode workspace config (Stage 3 bridge
  /// until [Workspace.defaultIdentityId] in Stage 4).
  PersonalIdentity? get activePersonal {
    final identity = state.byId(IdentityProvisioner.defaultPersonalId);
    if (identity is PersonalIdentity) return identity;
    final personals = state.personals;
    return personals.isEmpty ? null : personals.first;
  }

  /// Sets the active preset for a specific personal identity (the one the
  /// workspace was opened against). Falls back to [activePersonal] when
  /// [identityId] is empty or not a personal identity.
  Future<void> setPersonalPreset(String identityId, String presetId) async {
    final byId = identityId.isEmpty ? null : state.byId(identityId);
    final personal = byId is PersonalIdentity ? byId : activePersonal;
    if (personal == null) return;
    await savePersonal(personal.copyWith(activePresetId: presetId.trim()));
  }

  Future<void> _syncPersonalPlugins(PersonalIdentity personal) async {
    emit(state.copyWith(isSyncingPlugins: true));
    try {
      final catalog =
          await (_installedPluginsLoader?.call() ?? _pluginRepository.loadAll());
      await _pluginLinker.syncForIdentity(
        identityId: personal.id,
        pluginIds: personal.bundle.pluginIds,
        installed: catalog,
      );
    } catch (e) {
      appLogger.e('[personal-plugins] sync failed: $e');
    } finally {
      emit(state.copyWith(isSyncingPlugins: false));
    }
  }
}
