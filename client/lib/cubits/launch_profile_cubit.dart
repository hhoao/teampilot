import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/mcp_server.dart';
import '../models/plugin.dart';
import '../models/team_config.dart';
import '../models/team_roster_slot.dart';
import '../services/expert_hub/composite_expert_hub_source.dart';
import '../services/expert_hub/expert_member_materializer.dart';
import '../models/launch_profile.dart';
import '../repositories/mcp_repository.dart';
import '../repositories/plugin_repository.dart';
import '../repositories/launch_profile_repository.dart';
import '../repositories/session_repository.dart';
import '../services/cli/registry/cli_tool_registry.dart';
import '../services/provider/config_profile_service.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/mcp/profile_mcp_linker_service.dart';
import '../services/storage/launch_profile_provisioner.dart';
import '../utils/logging/logger.dart';
import '../utils/team/team_member_naming.dart';
import 'team/launch_profile_cubit_host.dart';
import 'team/model/launch_profile_state.dart';
import 'team/team_launch_service.dart';
import 'team/team_profile_provisioner.dart';
import 'team/team_resource_sync_service.dart';
import 'team/team_roster_editor.dart';

export 'team/model/launch_profile_state.dart';
export 'team/team_launch_service.dart' show TeamLauncher, CliExecutableResolver;
export 'team/team_resource_sync_service.dart'
    show mergeExtensionMcp, InstalledPluginsLoader, InstalledMcpLoader;

/// Owns workspace identity state (team) and coordinates resource
/// linking ([TeamResourceSyncService]), launching ([TeamLaunchService]) and
/// config-profile provisioning ([TeamProfileProvisioner]). Roster transforms
/// live in [TeamRosterEditor]; this cubit persists and emits.
class LaunchProfileCubit extends Cubit<LaunchProfileState>
    implements LaunchProfileCubitHost {
  LaunchProfileCubit({
    required LaunchProfileRepository repository,
    required SessionRepository sessionRepository,
    required String Function() executableResolver,
    CliExecutableResolver? cliExecutableResolver,
    TeamLauncher? launcher,
    String? Function()? llmConfigPathOverride,
    String appDataBasePath = '',
    ConfigProfileService? configProfileService,
    StorageRootsResolver? storageRootsResolver,
    SessionLifecycleService? lifecycleService,
    PluginRepository? pluginRepository,
    InstalledPluginsLoader? installedPluginsLoader,
    ProfileMcpLinkerService? mcpLinker,
    McpRepository? mcpRepository,
    InstalledMcpLoader? installedMcpLoader,
    Future<List<McpServer>> Function(String teamId)? extensionMcpContributor,
    LaunchProfileProvisioner? identityProvisioner,
    CompositeExpertHubSource? expertHubSource,
  }) : _repository = repository,
       _sessionRepository = sessionRepository,
       _identityProvisioner =
           identityProvisioner ??
           LaunchProfileProvisioner(repository: repository),
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
             configProfileService: configProfileService,
             storageRootsResolver: storageRootsResolver,
           ),
       _pluginRepository = pluginRepository ?? PluginRepository(),
       _installedPluginsLoader = installedPluginsLoader,
       _mcpLinker = mcpLinker ?? ProfileMcpLinkerService(),
       _mcpRepository = mcpRepository ?? McpRepository(),
       _installedMcpLoader = installedMcpLoader,
       _extensionMcpContributor = extensionMcpContributor ?? _noExtensionMcp,
       _launcher = launcher,
       _expertHubSource = expertHubSource,
       super(const LaunchProfileState());

  static Future<List<McpServer>> _noExtensionMcp(String teamId) async =>
      const <McpServer>[];

  final LaunchProfileRepository _repository;
  final SessionRepository _sessionRepository;
  final LaunchProfileProvisioner _identityProvisioner;
  final String Function() _executableResolver;
  final CliExecutableResolver? _cliExecutableResolver;
  final String _appDataBasePath;
  final ConfigProfileService? _configProfileService;
  final StorageRootsResolver? _storageRootsResolver;
  final SessionLifecycleService _lifecycle;
  final PluginRepository _pluginRepository;
  final InstalledPluginsLoader? _installedPluginsLoader;
  final ProfileMcpLinkerService _mcpLinker;
  final McpRepository _mcpRepository;
  final InstalledMcpLoader? _installedMcpLoader;
  final Future<List<McpServer>> Function(String teamId)
  _extensionMcpContributor;
  final TeamLauncher? _launcher;
  CompositeExpertHubSource? _expertHubSource;

  final TeamRosterEditor _rosterEditor = const TeamRosterEditor();

  /// Wire after bootstrap creates [CompositeExpertHubSource] so roster
  /// `hhoao/teampilot-resources/member-hub/*` keys resolve on load/clone.
  void attachExpertHubSource(CompositeExpertHubSource source) {
    _expertHubSource = source;
  }

  late final TeamProfileProvisioner _provisioner = TeamProfileProvisioner(
    configProfileService: _configProfileService,
    storageRootsResolver: _storageRootsResolver,
    appDataBasePathOverride: _appDataBasePath,
  );

  late final TeamResourceSyncService _sync = TeamResourceSyncService(
    host: this,
    provisioner: _provisioner,
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

  // ===== LaunchProfileCubitHost =====

  @override
  void applyState(LaunchProfileState next) {
    if (!isClosed) emit(next);
  }

  @override
  Future<void> saveTeamProfiles(List<TeamProfile> teams) async {
    for (final team in teams) {
      await _repository.save(team);
    }
  }

  Future<TeamProfile> _materializeTeam(TeamProfile team) =>
      ExpertMemberMaterializer.attachMaterializedMembers(
        team,
        source: _expertHubSource,
        localStore: _expertHubSource?.localStore,
      );

  Future<List<TeamProfile>> _materializeTeams(List<TeamProfile> teams) =>
      ExpertMemberMaterializer.attachMaterializedMembersAll(
        teams,
        source: _expertHubSource,
      );

  List<TeamProfile> _sortTeams(List<TeamProfile> teams) {
    final hasCustomOrder = teams.any((team) => team.sortOrder > 0);
    final sorted = List<TeamProfile>.of(teams);
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

  LaunchProfile? byId(String id) => state.byId(id);

  // ===== Launch / preview (delegated) =====

  String previewFor(
    TeamMemberConfig member, {
    String? workingDirectory,
    List<String> additionalDirectories = const [],
  }) => _launchService.previewFor(
    member,
    workingDirectory: workingDirectory,
    additionalDirectories: additionalDirectories,
  );

  String get selectedCommandPreview => _launchService.selectedCommandPreview;

  Future<void> launchMember(
    String memberId, {
    String? workingDirectory,
    List<String> additionalDirectories = const [],
  }) => _launchService.launchMember(
    memberId,
    workingDirectory: workingDirectory,
    additionalDirectories: additionalDirectories,
  );

  Future<void> launchSelectedTeam({
    String? workingDirectory,
    List<String> additionalDirectories = const [],
  }) => _launchService.launchSelectedTeam(
    workingDirectory: workingDirectory,
    additionalDirectories: additionalDirectories,
  );

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
  }

  Future<void> removeSkillFromAllTeams(String skillId) async {
    await _sync.removeSkillFromAllTeams(skillId);
  }

  Future<void> removePluginFromAllTeams(String pluginId) async {
    await _sync.removePluginFromAllTeams(pluginId);
  }

  // ===== Team lifecycle =====

  Future<void> load({
    bool awaitProfiles = false,
    bool bootSilent = false,
  }) async {
    final sw = Stopwatch()..start();
    appLogger.i('[boot] LaunchProfileCubit load start');
    if (!bootSilent) {
      emit(state.copyWith(isLoading: true));
    }
    final loadSw = Stopwatch()..start();
    var all = await _repository.loadAll();
    appLogger.i(
      '[boot] LaunchProfileCubit loadAll +${loadSw.elapsedMilliseconds}ms '
      'count=${all.length}',
    );
    final builtInTeams = await _identityProvisioner.ensureDefaultTeams(
      buildNative: _rosterEditor.defaultNativeTeam,
      buildMixed: _rosterEditor.defaultMixedTeam,
      loaded: all,
    );
    for (final team in [builtInTeams.native, builtInTeams.mixed]) {
      if (!all.any((profile) => profile.id == team.id)) {
        all = List<LaunchProfile>.of(all)..add(team);
      }
    }
    var teams = _sortTeams(all.whereType<TeamProfile>().toList());
    teams = [
      for (final t in teams)
        _rosterEditor.normalizeTeam(
          t.roster.isEmpty
              ? t.copyWith(roster: TeamMemberNaming.defaultRoster())
              : t,
        ),
    ];
    teams = await _materializeTeams(teams);
    final selectedId = state.selectedTeamId;
    final nextSelected =
        selectedId != null && teams.any((team) => team.id == selectedId)
        ? selectedId
        : (teams.isEmpty ? null : teams.first.id);
    emit(
      state.copyWith(
        identities: [...teams],
        selectedTeamId: nextSelected,
        isLoading: false,
        statusMessage: 'Ready.',
      ),
    );
    appLogger.i(
      '[boot] LaunchProfileCubit load done +${sw.elapsedMilliseconds}ms '
      '${teams.length} teams',
    );
    final profiles = _provisioner.ensureForTeams(teams);
    if (awaitProfiles) {
      await profiles;
    } else {
      unawaited(
        profiles.catchError((Object e) {
          appLogger.w(
            '[LaunchProfileCubit] background profile ensure failed: $e',
          );
        }),
      );
    }
  }

  /// Selects the active team. [syncResources] runs plugin/MCP linker sync
  /// (expensive; skip when browsing teams in the home workspace). [silent]
  /// avoids a status-line emit that would rebuild listeners.
  Future<void> selectTeam(
    String id, {
    bool syncResources = true,
    bool silent = false,
  }) async {
    if (!state.teams.any((team) => team.id == id)) return;
    final team = state.teams.firstWhere((t) => t.id == id);
    emit(
      state.copyWith(
        selectedTeamId: id,
        statusMessage: silent ? state.statusMessage : 'Selected ${team.name}.',
      ),
    );
    if (!syncResources) return;
    unawaited(Future.wait([_sync.syncPluginsForSelected(), _sync.syncMcp()]));
  }

  Future<bool> addTeam(
    String name, {
    CliTool cli = CliTool.claude,
    TeamMode teamMode = TeamMode.native,
    Map<String, String> providerIdsByTool = const {},
    List<TeamRosterSlot>? roster,
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
    final team = TeamProfile(
      id: teamId,
      name: trimmed,
      description: description.trim(),
      cli: cli,
      teamMode: teamMode,
      providerIdsByTool: providerIdsByTool,
      skillIds: skillIds,
      createdAt: now,
      roster: roster ?? TeamMemberNaming.defaultRoster(joinedAt: now),
    );
    final materialized = await _materializeTeam(
      _rosterEditor.normalizeTeam(team),
    );
    final teams = [...state.teams, materialized];
    emit(
      state.copyWith(
        teams: teams,
        selectedTeamId: materialized.id,
        statusMessage: 'Added ${materialized.name}.',
      ),
    );
    await saveTeamProfiles(teams);
    await _provisioner.ensureTeamProfile(
      materialized.id,
      cli: materialized.cli,
    );
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
    required List<TeamRosterSlot> roster,
    List<String> skillIds = const [],
    List<String> pluginIds = const [],
    List<String> mcpServerIds = const [],
    String description = '',
    String extraArgs = '',
    String? hubSourceKey,
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
    final nextRoster = roster.isEmpty
        ? TeamMemberNaming.defaultRoster(joinedAt: now)
        : roster;
    final normalized = _rosterEditor.normalizeTeam(
      TeamProfile(
        id: teamId,
        name: displayName,
        description: description,
        extraArgs: extraArgs,
        cli: cli,
        teamMode: teamMode,
        createdAt: now,
        roster: nextRoster,
        skillIds: skillIds,
        pluginIds: pluginIds,
        mcpServerIds: mcpServerIds,
        hubSourceKey: hubSourceKey,
      ),
    );
    final materialized = await _materializeTeam(normalized);
    final teams = [...state.teams, materialized];
    emit(
      state.copyWith(
        teams: teams,
        selectedTeamId: materialized.id,
        statusMessage: 'Cloned ${materialized.name}.',
      ),
    );
    await saveTeamProfiles(teams);
    await _provisioner.ensureTeamProfile(
      materialized.id,
      cli: materialized.cli,
    );
    unawaited(_sync.syncPluginsForSelected());
    return materialized.id;
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
    await saveTeamProfiles(teams);
    return true;
  }

  Future<void> updateSelected(TeamProfile updated) async {
    final selected = state.selectedTeam;
    if (selected == null) return;
    final pluginsChanged = !listEquals(selected.pluginIds, updated.pluginIds);
    final mcpChanged = !listEquals(selected.mcpServerIds, updated.mcpServerIds);
    final launchNormalized = updated.normalizedLaunchConfig();
    final normalized = _rosterEditor.normalizeTeam(
      launchNormalized.roster.isEmpty
          ? launchNormalized.copyWith(roster: TeamMemberNaming.defaultRoster())
          : launchNormalized,
    );
    final materialized = await _materializeTeam(normalized);
    final teams = [
      for (final team in state.teams)
        if (team.id == selected.id) materialized else team,
    ];
    emit(
      state.copyWith(
        teams: teams,
        selectedTeamId: materialized.id,
        statusMessage: materialized.isValid
            ? 'Saved ${materialized.name}.'
            : 'Name is required.',
      ),
    );
    await _repository.save(materialized);
    if (pluginsChanged) {
      await _sync.syncPluginsForSelected();
    }
    if (mcpChanged) {
      await _sync.syncMcp();
    }
  }

  /// Launch-config-only persist: no Expert Hub rematerialize, one profile write.
  ///
  /// Returns the persisted team, or `null` when no team is selected.
  Future<TeamProfile?> _persistSelectedLaunchConfig(TeamProfile updated) async {
    final selected = state.selectedTeam;
    if (selected == null) return null;
    final normalized = updated.normalizedLaunchConfig();
    final next = ExpertMemberMaterializer.reapplyLaunchInheritance(normalized);
    final teams = [
      for (final team in state.teams)
        if (team.id == selected.id) next else team,
    ];
    emit(
      state.copyWith(
        teams: teams,
        selectedTeamId: next.id,
        statusMessage: next.isValid
            ? 'Saved ${next.name}.'
            : 'Name is required.',
      ),
    );
    await _repository.save(next);
    return next;
  }

  Future<void> deleteTeam(String id) async {
    final deleted = state.teams.where((team) => team.id == id).firstOrNull;
    if (deleted == null) return;
    for (final session in await _sessionRepository.loadSessions()) {
      if (session.sessionTeam.trim() == id) {
        await _sessionRepository.deleteSession(session.sessionId);
      }
    }
    await _repository.delete(id);
    var teams = state.teams.where((team) => team.id != id).toList();
    if (teams.isEmpty) {
      final builtIn = await _identityProvisioner.ensureDefaultTeams(
        buildNative: _rosterEditor.defaultNativeTeam,
        buildMixed: _rosterEditor.defaultMixedTeam,
      );
      teams = _sortTeams([builtIn.native, builtIn.mixed]);
    }
    final nextSelected = state.selectedTeamId == id
        ? teams.first.id
        : state.selectedTeamId ?? teams.first.id;
    emit(
      state.copyWith(
        teams: teams,
        selectedTeamId: nextSelected,
        statusMessage: 'Deleted ${deleted.name}.',
      ),
    );
    await saveTeamProfiles(teams);
    unawaited(_sync.syncPluginsForSelected());
  }

  Future<void> deleteSelected() async {
    final selected = state.selectedTeam;
    if (selected == null) return;
    await deleteTeam(selected.id);
  }

  // ===== Members =====

  /// Appends an expert reference to the team with [teamId].
  Future<TeamRosterSlot?> addExpertToTeam(
    String teamId,
    String expertKey, {
    String? slotIdHint,
    TeamRosterSlotOverrides? overrides,
  }) async {
    final index = state.teams.indexWhere((team) => team.id == teamId);
    if (index < 0) return null;
    final team = state.teams[index];
    final (team: updated, :added) = _rosterEditor.addExpertToTeam(
      team,
      expertKey,
      overrides: overrides,
      slotIdHint: slotIdHint,
    );
    final normalized = _rosterEditor.normalizeTeam(updated);
    final materialized = await _materializeTeam(normalized);
    final teams = [
      for (final t in state.teams)
        if (t.id == teamId) materialized else t,
    ];
    emit(state.copyWith(teams: teams, statusMessage: 'Added ${added.id}.'));
    await saveTeamProfiles(teams);
    return added;
  }

  /// Returns the updated member of the selected team after persisting, or
  /// `null` when the team is missing or the mutation was rejected.
  Future<TeamProfile?> updateMember(
    String memberId,
    TeamMemberConfig updated,
  ) async {
    final team = state.selectedTeam;
    if (team == null) return null;
    final mutation = _rosterEditor.updateMemberOverrides(
      team,
      memberId,
      updated,
    );
    if (mutation.isRejected) {
      emit(state.copyWith(statusMessage: mutation.statusMessage));
      return null;
    }
    await updateSelected(mutation.team!);
    return state.selectedTeam;
  }

  /// Swaps the catalog expert referenced by a roster slot (persona is
  /// materialized at load/connect — not copied into team JSON).
  Future<void> setMemberExpert(String memberId, String expertKey) async {
    final team = state.selectedTeam;
    if (team == null) return;
    final slot = _rosterEditor.slotById(team, memberId);
    if (slot == null) return;
    final key = expertKey.trim();
    if (key.isEmpty || key == slot.expertKey) return;
    final mutation = _rosterEditor.updateSlot(
      team,
      memberId,
      slot.copyWith(expertKey: key),
    );
    if (mutation.isRejected) {
      emit(state.copyWith(statusMessage: mutation.statusMessage));
      return;
    }
    await updateSelected(mutation.team!);
  }

  /// Sets the active preset for the selected team.
  ///
  /// [presetId] may be a preset UUID, `null` (clear), or empty (clear).
  /// [syncCli] aligns [TeamProfile.cli] with the preset for mixed/native launch.
  /// Completes after the selected profile is persisted (no hub rematerialize).
  /// Returns the persisted team, or `null` when no team is selected.
  Future<TeamProfile?> setTeamActivePreset(
    String? presetId, {
    CliTool? syncCli,
  }) async {
    final team = state.selectedTeam;
    if (team == null) return null;
    final effectiveId = (presetId == null || presetId.trim().isEmpty)
        ? null
        : presetId.trim();
    final TeamProfile next;
    if (effectiveId == null) {
      next = team.copyWith(activePresetId: null, updateActivePresetId: true);
    } else {
      next = team.asPresetLaunch(effectiveId, syncCli: syncCli);
    }
    return _persistSelectedLaunchConfig(next);
  }

  /// Persists team custom launch defaults for [catalogCli] and clears any preset.
  ///
  /// Completes after the selected profile is persisted (no hub rematerialize).
  /// Returns the persisted team, or `null` when no team is selected.
  Future<TeamProfile?> updateTeamCustomLaunch({
    required CliTool catalogCli,
    CliTool? defaultCli,
    required String providerId,
    required String model,
    required String effort,
  }) async {
    final team = state.selectedTeam;
    if (team == null) return null;
    var next = team.asCustomLaunch(
      cli: catalogCli,
      providerId: providerId,
      model: model,
      effort: effort,
    );
    if (defaultCli != null && team.teamMode == TeamMode.mixed) {
      next = next.copyWith(cli: defaultCli);
    }
    return _persistSelectedLaunchConfig(next);
  }

  /// Sets the active preset for a member of the selected team.
  ///
  /// [presetId] may be a preset UUID ([CliPreset.id]),
  /// [TeamProfile.inheritPresetId] to inherit the team default, `null` (custom),
  /// or empty (custom).
  ///
  /// In [TeamMode.mixed], [syncCli] is required when selecting an explicit preset.
  ///
  /// Returns the updated selected team, or `null` when it is missing or the
  /// slot mutation was rejected.
  Future<TeamProfile?> setMemberActivePreset(
    String memberId,
    String? presetId, {
    CliTool? syncCli,
  }) async {
    final team = state.selectedTeam;
    if (team == null) return null;
    final slot = _rosterEditor.slotById(team, memberId);
    if (slot == null) return null;
    final overrides = slot.overrides;
    final effectiveId = (presetId == null || presetId.trim().isEmpty)
        ? null
        : presetId.trim();

    TeamRosterSlotOverrides nextOverrides;
    if (effectiveId == TeamProfile.inheritPresetId) {
      nextOverrides = TeamRosterSlotOverrides(
        provider: '',
        model: '',
        effort: '',
        extraArgs: overrides.extraArgs,
        cli: null,
        replicas: overrides.replicas,
        capabilities: overrides.capabilities,
        activePresetId: TeamProfile.inheritPresetId,
        launchSecurityPolicy: overrides.launchSecurityPolicy,
      );
    } else if (effectiveId == null) {
      nextOverrides = TeamRosterSlotOverrides(
        provider: overrides.provider,
        model: overrides.model,
        effort: overrides.effort,
        extraArgs: overrides.extraArgs,
        cli: overrides.cli,
        replicas: overrides.replicas,
        capabilities: overrides.capabilities,
        activePresetId: null,
        launchSecurityPolicy: overrides.launchSecurityPolicy,
      );
    } else {
      final syncCliFromPreset =
          team.teamMode == TeamMode.mixed && syncCli != null;
      nextOverrides = TeamRosterSlotOverrides(
        provider: '',
        model: '',
        effort: '',
        extraArgs: overrides.extraArgs,
        cli: syncCliFromPreset ? syncCli : overrides.cli,
        replicas: overrides.replicas,
        capabilities: overrides.capabilities,
        activePresetId: effectiveId,
        launchSecurityPolicy: overrides.launchSecurityPolicy,
      );
    }
    final mutation = _rosterEditor.updateSlot(
      team,
      memberId,
      slot.copyWith(overrides: nextOverrides),
    );
    if (mutation.isRejected) {
      emit(state.copyWith(statusMessage: mutation.statusMessage));
      return null;
    }
    await updateSelected(mutation.team!);
    return state.selectedTeam;
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

  /// Updates provider override on roster slots when an LLM provider is renamed.
  Future<void> renameLlmProviderReference(String from, String to) async {
    if (from == to) return;
    var changed = false;
    final teams = <TeamProfile>[];
    for (final team in state.teams) {
      var teamChanged = false;
      final roster = <TeamRosterSlot>[];
      for (final slot in team.roster) {
        if (slot.overrides.provider == from) {
          teamChanged = true;
          changed = true;
          roster.add(
            slot.copyWith(overrides: slot.overrides.copyWith(provider: to)),
          );
        } else {
          roster.add(slot);
        }
      }
      teams.add(teamChanged ? team.copyWith(roster: roster) : team);
    }
    if (!changed) return;
    emit(state.copyWith(teams: teams));
    await saveTeamProfiles(teams);
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

  /// Sets [presetId] as the active preset on every team.
  Future<void> applyDefaultPresetToAllIdentities(String presetId) async {
    final trimmed = presetId.trim();
    if (trimmed.isEmpty) return;

    var teamsChanged = false;
    final teams = <TeamProfile>[];
    for (final team in state.teams) {
      if (team.activePresetId == trimmed) {
        teams.add(team);
        continue;
      }
      teamsChanged = true;
      teams.add(team.asPresetLaunch(trimmed));
    }
    if (teamsChanged) {
      emit(state.copyWith(teams: teams));
      await saveTeamProfiles(teams);
    }
  }
}
