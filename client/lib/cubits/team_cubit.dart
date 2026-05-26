import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_session.dart';
import '../models/plugin.dart';
import '../models/skill.dart';
import '../models/team_config.dart';
import '../repositories/plugin_repository.dart';
import '../repositories/team_repository.dart';
import '../services/storage/app_storage.dart';
import '../services/cli/cli_data_layout.dart';
import '../services/provider/config_profile_service.dart';
import '../services/session/launch_command_builder.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/plugin/team_plugin_linker_service.dart';
import '../services/skill/team_skill_linker_service.dart';
import '../utils/logger.dart';
import '../utils/team_member_naming.dart';

class TeamState extends Equatable {
  const TeamState({
    this.teams = const [],
    this.selectedTeamId,
    this.statusMessage = '',
    this.isLoading = true,
    this.isLaunching = false,
    this.isSyncingSkills = false,
    this.isSyncingPlugins = false,
    this.pluginSyncConflicts = const {},
  });

  final List<TeamConfig> teams;
  final String? selectedTeamId;
  final String statusMessage;
  final bool isLoading;
  final bool isLaunching;
  final bool isSyncingSkills;
  final bool isSyncingPlugins;
  /// Plugin ids on the selected team that were linked under a fallback dir name.
  final Map<String, String> pluginSyncConflicts;

  TeamConfig? get selectedTeam {
    for (final team in teams) {
      if (team.id == selectedTeamId) return team;
    }
    return teams.isEmpty ? null : teams.first;
  }

  TeamState copyWith({
    List<TeamConfig>? teams,
    String? selectedTeamId,
    String? statusMessage,
    bool? isLoading,
    bool? isLaunching,
    bool? isSyncingSkills,
    bool? isSyncingPlugins,
    Map<String, String>? pluginSyncConflicts,
    bool clearSelectedTeamId = false,
  }) {
    return TeamState(
      teams: teams ?? this.teams,
      selectedTeamId: clearSelectedTeamId
          ? null
          : (selectedTeamId ?? this.selectedTeamId),
      statusMessage: statusMessage ?? this.statusMessage,
      isLoading: isLoading ?? this.isLoading,
      isLaunching: isLaunching ?? this.isLaunching,
      isSyncingSkills: isSyncingSkills ?? this.isSyncingSkills,
      isSyncingPlugins: isSyncingPlugins ?? this.isSyncingPlugins,
      pluginSyncConflicts: pluginSyncConflicts ?? this.pluginSyncConflicts,
    );
  }

  @override
  List<Object?> get props => [
    teams,
    selectedTeamId,
    statusMessage,
    isLoading,
    isLaunching,
    isSyncingSkills,
    isSyncingPlugins,
    pluginSyncConflicts,
  ];
}

typedef TeamLauncher =
    Future<void> Function(TeamConfig team, TeamMemberConfig member);
typedef StringProvider = String Function();
typedef CliExecutableResolver = String Function(TeamCli cli);
typedef InstalledSkillsLoader = Future<List<Skill>> Function();
typedef InstalledPluginsLoader = Future<List<Plugin>> Function();

class TeamCubit extends Cubit<TeamState> {
  TeamCubit({
    required TeamRepository repository,
    required String Function() executableResolver,
    CliExecutableResolver? cliExecutableResolver,
    TeamLauncher? launcher,
    String? Function()? llmConfigPathOverride,
    String appDataBasePath = '',
    ConfigProfileService? configProfileService,
    StorageRootsResolver? storageRootsResolver,
    SessionLifecycleService? lifecycleService,
    TeamSkillLinkerService? skillLinker,
    InstalledSkillsLoader? installedSkillsLoader,
    TeamPluginLinkerService? pluginLinker,
    PluginRepository? pluginRepository,
    InstalledPluginsLoader? installedPluginsLoader,
  }) : _repository = repository,
       _executableResolver = executableResolver,
       _cliExecutableResolver = cliExecutableResolver,
       _appDataBasePathOverride = appDataBasePath.isNotEmpty
           ? appDataBasePath
           : null,
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
       _skillLinker = skillLinker ?? TeamSkillLinkerService(),
       _installedSkillsLoader = installedSkillsLoader,
       _pluginLinker = pluginLinker ?? TeamPluginLinkerService(),
       _pluginRepository = pluginRepository ?? PluginRepository(),
       _installedPluginsLoader = installedPluginsLoader,
       _launcher = launcher,
       super(const TeamState());

  final TeamRepository _repository;
  final TeamLauncher? _launcher;
  final String Function() _executableResolver;
  final CliExecutableResolver? _cliExecutableResolver;
  final String? _appDataBasePathOverride;
  final ConfigProfileService? _configProfileService;

  String get _resolvedAppDataBasePath {
    final override = _appDataBasePathOverride;
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return AppStorage.paths.basePath;
  }

  final StorageRootsResolver? _storageRootsResolver;
  final SessionLifecycleService _lifecycle;
  final TeamSkillLinkerService _skillLinker;
  final InstalledSkillsLoader? _installedSkillsLoader;
  final TeamPluginLinkerService _pluginLinker;
  final PluginRepository _pluginRepository;
  final InstalledPluginsLoader? _installedPluginsLoader;

  /// Fire-and-forget skill/plugin sync can finish after [close]; skip emit.
  void _safeEmit(TeamState newState) {
    if (!isClosed) emit(newState);
  }

  Future<Map<String, String>?> _buildLaunchEnvironment(
    TeamConfig team, {
    TeamMemberConfig? member,
  }) async {
    final runtimeTeamName = team.name.trim();
    final plan = await _lifecycle.prepareLaunch(
      session: AppSession(
        sessionId: runtimeTeamName,
        projectId: '',
        primaryPath: AppStorage.cwd,
        sessionTeam: team.id,
        launchTeam: runtimeTeamName,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
      team: team,
      member: member,
    );
    return plan.env.isEmpty ? null : plan.env;
  }

  Future<ConfigProfileService> _profileService() async {
    final injected = _configProfileService;
    if (injected != null) return injected;
    final resolver = _storageRootsResolver;
    if (resolver == null) {
      final fs = AppStorage.fs;
      return ConfigProfileService(
        basePath: _resolvedAppDataBasePath,
        fs: fs,
        layout: CliDataLayout(teampilotRoot: _resolvedAppDataBasePath, fs: fs),
      );
    }
    final roots = await resolver();
    return ConfigProfileService(
      basePath: roots.teampilotRoot,
      fs: roots.fs,
      layout: roots.layout,
    );
  }

  Future<void> _ensureProfilesForTeams(List<TeamConfig> teams) async {
    final profileService = await _profileService();
    for (final team in teams) {
      await profileService.ensureTeamProfile(team.id, cli: team.cli);
    }
  }

  Future<void> _runLaunch(TeamConfig team, TeamMemberConfig member) async {
    final env = await _buildLaunchEnvironment(team, member: member);
    final launch =
        _launcher ??
        (t, m) => LaunchCommandBuilder.launch(
          t,
          member: m,
          executable: _resolveExecutableFor(t.cli),
          extraEnvironment: env,
        );
    await launch(team, member);
  }

  String _resolveExecutableFor(TeamCli cli) {
    return _cliExecutableResolver?.call(cli) ?? _executableResolver();
  }

  String previewFor(TeamMemberConfig member) {
    final team = state.selectedTeam;
    return team == null
        ? ''
        : LaunchCommandBuilder.preview(
            team,
            member,
            executable: _resolveExecutableFor(team.cli),
          );
  }

  String get selectedCommandPreview {
    final team = state.selectedTeam;
    if (team == null || team.members.isEmpty) return '';
    return LaunchCommandBuilder.preview(
      team,
      team.members.first,
      executable: _resolveExecutableFor(team.cli),
    );
  }

  Future<void> load({bool awaitProfiles = false}) async {
    appLogger.i('TeamCubit loading teams...');
    emit(state.copyWith(isLoading: true));
    var teams = await _repository.loadTeams();
    if (teams.isEmpty) {
      teams = [_defaultTeam()];
      await _repository.saveTeams(teams);
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
    final profiles = _ensureProfilesForTeams(teams);
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
      _syncSkillsForSelected(),
      _syncPluginsForSelected(),
    ]);
  }

  Future<void> syncSelectedTeamSkills({List<Skill>? installed}) async {
    await _syncSkillsForSelected(installed: installed);
  }

  Future<void> syncSelectedTeamPlugins({List<Plugin>? installed}) async {
    await _syncPluginsForSelected(installed: installed);
  }

  Future<void> syncTeamsUsingPlugin(
    String pluginId, {
    List<Plugin>? installed,
  }) async {
    final teamIds = [
      for (final team in state.teams)
        if (team.pluginIds.contains(pluginId)) team.id,
    ];
    await _syncPluginsForTeamIds(teamIds, installed: installed);
  }

  Future<void> removeSkillFromAllTeams(String skillId) async {
    final selected = state.selectedTeam;
    final syncNeeded = selected != null && selected.skillIds.contains(skillId);
    var changed = false;
    final teams = [
      for (final team in state.teams)
        if (team.skillIds.contains(skillId))
          () {
            changed = true;
            return team.copyWith(
              skillIds: team.skillIds
                  .where((id) => id != skillId)
                  .toList(growable: false),
            );
          }()
        else
          team,
    ];
    if (!changed) return;
    emit(state.copyWith(teams: teams));
    await _repository.saveTeams(teams);
    if (syncNeeded) {
      await _syncSkillsForSelected();
    }
  }

  Future<void> _syncSkillsForSelected({List<Skill>? installed}) async {
    final team = state.selectedTeam;
    if (team == null) return;

    _safeEmit(state.copyWith(isSyncingSkills: true));
    try {
      final List<Skill> catalog;
      if (installed != null) {
        catalog = installed;
      } else {
        catalog =
            await (_installedSkillsLoader?.call() ??
                Future.value(const <Skill>[]));
      }
      final enabled = catalog.where((s) => s.enabled).toList(growable: false);

      var result = await _skillLinker.syncForTeam(
        teamId: team.id,
        skillIds: team.skillIds,
        installed: enabled,
      );

      if (result.skippedMissingIds.isNotEmpty) {
        final prunedIds = team.skillIds
            .where((id) => !result.skippedMissingIds.contains(id))
            .toList(growable: false);
        if (prunedIds.length != team.skillIds.length) {
          final prunedTeam = team.copyWith(skillIds: prunedIds);
          final teams = [
            for (final t in state.teams)
              if (t.id == team.id) prunedTeam else t,
          ];
          _safeEmit(state.copyWith(teams: teams));
          await _repository.saveTeams(teams);
          result = await _skillLinker.syncForTeam(
            teamId: team.id,
            skillIds: prunedIds,
            installed: enabled,
          );
        }
      }

      var status = state.statusMessage;
      if (result.linked.isNotEmpty) {
        status = 'Linked ${result.linked.length} skill(s) for ${team.name}.';
      } else if (team.skillIds.isEmpty) {
        status = 'Cleared CLI skills for ${team.name}.';
      }
      if (result.skippedMissingIds.isNotEmpty) {
        status =
            '$status Removed ${result.skippedMissingIds.length} missing skill(s).';
      }
      if (result.errors.isNotEmpty) {
        status = result.errors.first;
        appLogger.w('[team-skills] sync errors: ${result.errors}');
      }
      _safeEmit(state.copyWith(statusMessage: status));
    } catch (e) {
      appLogger.e('[team-skills] sync failed: $e');
      _safeEmit(state.copyWith(statusMessage: 'Skill sync failed: $e'));
    } finally {
      _safeEmit(state.copyWith(isSyncingSkills: false));
    }
  }

  Future<void> _syncPluginsForSelected({List<Plugin>? installed}) async {
    final team = state.selectedTeam;
    if (team == null) return;
    await _syncPluginsForTeamIds([team.id], installed: installed);
  }

  Future<void> _syncPluginsForTeamIds(
    Iterable<String> teamIds, {
    List<Plugin>? installed,
  }) async {
    final ids = teamIds.toList(growable: false);
    if (ids.isEmpty) return;

    _safeEmit(state.copyWith(isSyncingPlugins: true));
    try {
      final catalog = installed ??
          await (_installedPluginsLoader?.call() ??
              _pluginRepository.loadAll());

      var conflicts = state.pluginSyncConflicts;
      for (final teamId in ids) {
        TeamConfig? team;
        for (final candidate in state.teams) {
          if (candidate.id == teamId) {
            team = candidate;
            break;
          }
        }
        if (team == null) continue;

        final result = await _pluginLinker.syncForTeam(
          teamId: team.id,
          pluginIds: team.pluginIds,
          installed: catalog,
        );

        if (result.skippedMissingIds.isNotEmpty) {
          appLogger.w(
            '[team-plugins] skipped missing for ${team.id}: '
            '${result.skippedMissingIds}',
          );
        }

        if (result.errors.isNotEmpty) {
          appLogger.w(
            '[team-plugins] sync errors for ${team.id}: ${result.errors}',
          );
          if (team.id == state.selectedTeamId) {
            _safeEmit(
              state.copyWith(
                statusMessage:
                    'Plugin sync had ${result.errors.length} error(s): '
                    '${result.errors.first}',
              ),
            );
          }
        }

        if (team.id == state.selectedTeamId) {
          conflicts = {
            for (final resolution in result.conflictResolutions)
              resolution.$1: resolution.$2,
          };
        }
      }

      _safeEmit(state.copyWith(pluginSyncConflicts: conflicts));
    } catch (e) {
      appLogger.e('[team-plugins] sync failed: $e');
    } finally {
      _safeEmit(state.copyWith(isSyncingPlugins: false));
    }
  }

  Future<void> removePluginFromAllTeams(String pluginId) async {
    final affectedTeamIds = [
      for (final team in state.teams)
        if (team.pluginIds.contains(pluginId)) team.id,
    ];
    if (affectedTeamIds.isEmpty) return;

    final teams = [
      for (final team in state.teams)
        if (team.pluginIds.contains(pluginId))
          team.copyWith(
            pluginIds: team.pluginIds
                .where((id) => id != pluginId)
                .toList(growable: false),
          )
        else
          team,
    ];
    emit(state.copyWith(teams: teams));
    await _repository.saveTeams(teams);
    await _syncPluginsForTeamIds(affectedTeamIds);
  }

  Future<bool> addTeam(String name, {TeamCli cli = TeamCli.flashskyai}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      emit(state.copyWith(statusMessage: 'Team name is required.'));
      return false;
    }
    if (state.teams.any((t) => t.name == trimmed)) {
      emit(state.copyWith(statusMessage: 'Team "$trimmed" already exists.'));
      return false;
    }
    if (!cli.isLaunchSupported) {
      emit(
        state.copyWith(
          statusMessage: 'CLI "${cli.value}" is not available for teams yet.',
        ),
      );
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final team = TeamConfig(
      id: trimmed,
      name: trimmed,
      cli: cli,
      createdAt: now,
      members: TeamMemberNaming.defaultRoster(joinedAt: now),
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
    final profileService = await _profileService();
    await profileService.ensureTeamProfile(team.id, cli: team.cli);
    unawaited(_syncSkillsForSelected());
    unawaited(_syncPluginsForSelected());
    return true;
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
  Future<void> bindClaudeProviderForTeamsWithoutBinding(String providerId) async {
    final trimmed = providerId.trim();
    if (trimmed.isEmpty) return;

    var changed = false;
    final teams = <TeamConfig>[];
    for (final team in state.teams) {
      if (team.cli != TeamCli.claude) {
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
          providerIdsByTool: {
            ...team.providerIdsByTool,
            'claude': trimmed,
          },
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
    final skillsChanged = !listEquals(selected.skillIds, updated.skillIds);
    final pluginsChanged =
        !listEquals(selected.pluginIds, updated.pluginIds);
    final normalized = _normalizeTeam(
      updated.members.isEmpty
          ? updated.copyWith(
              members: TeamMemberNaming.defaultRoster(),
            )
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
    if (skillsChanged) {
      await _syncSkillsForSelected();
    }
    if (pluginsChanged) {
      await _syncPluginsForSelected();
    }
  }

  Future<void> deleteSelected() async {
    final selected = state.selectedTeam;
    if (selected == null) return;
    await _repository.deleteTeam(selected.name, cliStateTeamId: selected.id);
    var teams = state.teams.where((team) => team.id != selected.id).toList();
    if (teams.isEmpty) teams = [_defaultTeam()];
    emit(
      state.copyWith(
        teams: teams,
        selectedTeamId: teams.first.id,
        statusMessage: 'Deleted ${selected.name}.',
      ),
    );
    await _repository.saveTeams(teams);
    unawaited(_syncSkillsForSelected());
    unawaited(_syncPluginsForSelected());
  }

  Future<void> addMember() async {
    final team = state.selectedTeam;
    if (team == null) return;
    final slug = _uniqueMemberSlug(team, 'member');
    final now = DateTime.now().millisecondsSinceEpoch;
    final member = TeamMemberConfig(id: slug, name: slug, joinedAt: now);
    await updateSelected(team.copyWith(members: [...team.members, member]));
    emit(state.copyWith(statusMessage: 'Added ${member.name}.'));
  }

  Future<void> updateMember(String memberId, TeamMemberConfig updated) async {
    final team = state.selectedTeam;
    if (team == null) return;
    final error = TeamMemberNaming.validateMemberName(updated.name);
    if (error != null) {
      emit(
        state.copyWith(
          statusMessage: error == 'at_sign'
              ? 'Member name cannot contain @.'
              : 'Member name is required.',
        ),
      );
      return;
    }
    final normalized = _normalizeMember(updated);
    await updateSelected(
      team.copyWith(
        members: [
          for (final m in team.members)
            if (m.id == memberId) normalized else m,
        ],
      ),
    );
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

  Future<void> deleteMember(String memberId) async {
    final team = state.selectedTeam;
    if (team == null) return;
    TeamMemberConfig? target;
    for (final m in team.members) {
      if (m.id == memberId) {
        target = m;
        break;
      }
    }
    if (target != null && TeamMemberNaming.isTeamLead(target)) {
      emit(
        state.copyWith(
          statusMessage: 'Cannot remove team-lead from the roster.',
        ),
      );
      return;
    }
    if (team.members.length == 1) {
      emit(state.copyWith(statusMessage: 'A team needs at least one member.'));
      return;
    }
    final deleted = team.members.firstWhere((m) => m.id == memberId);
    await updateSelected(
      team.copyWith(
        members: team.members
            .where((m) => m.id != memberId)
            .toList(growable: false),
      ),
    );
    emit(state.copyWith(statusMessage: 'Deleted ${deleted.name}.'));
  }

  Future<void> launchMember(String memberId) async {
    final team = state.selectedTeam;
    if (team == null || team.name.trim().isEmpty) {
      emit(state.copyWith(statusMessage: 'Team name is required.'));
      return;
    }
    final member = team.members.firstWhere(
      (m) => m.id == memberId,
      orElse: () => const TeamMemberConfig(id: '', name: ''),
    );
    if (!member.isValid) {
      emit(state.copyWith(statusMessage: 'Member name is required.'));
      return;
    }
    emit(
      state.copyWith(
        isLaunching: true,
        statusMessage: 'Starting ${member.name}...',
      ),
    );
    try {
      await syncSelectedTeamPlugins();
      await _runLaunch(team, member);
      emit(
        state.copyWith(
          isLaunching: false,
          statusMessage:
              'Started ${member.name}: ${LaunchCommandBuilder.preview(team, member, executable: _resolveExecutableFor(team.cli))}',
        ),
      );
    } on Object catch (error) {
      emit(
        state.copyWith(
          isLaunching: false,
          statusMessage: 'Launch failed: $error',
        ),
      );
    }
  }

  Future<void> launchSelectedTeam() async {
    final team = state.selectedTeam;
    if (team == null || team.name.trim().isEmpty) {
      emit(state.copyWith(statusMessage: 'Team name is required.'));
      return;
    }
    final validMembers = team.members.where((m) => m.isValid).toList();
    if (validMembers.isEmpty) {
      emit(
        state.copyWith(statusMessage: 'At least one valid member is required.'),
      );
      return;
    }
    emit(
      state.copyWith(
        isLaunching: true,
        statusMessage: 'Starting ${validMembers.length} members...',
      ),
    );
    try {
      await syncSelectedTeamPlugins();
      for (final member in validMembers) {
        await _runLaunch(team, member);
      }
      emit(
        state.copyWith(
          isLaunching: false,
          statusMessage: 'Started ${validMembers.length} members.',
        ),
      );
    } on Object catch (error) {
      emit(
        state.copyWith(
          isLaunching: false,
          statusMessage: 'Launch failed: $error',
        ),
      );
    }
  }

  TeamConfig _defaultTeam() {
    const name = 'Default Team';
    final now = DateTime.now().millisecondsSinceEpoch;
    return TeamConfig(
      id: name,
      name: name,
      createdAt: now,
      members: TeamMemberNaming.defaultRoster(joinedAt: now),
    );
  }

  TeamMemberConfig _defaultMember({int? now}) {
    final ts = now ?? DateTime.now().millisecondsSinceEpoch;
    return TeamMemberNaming.defaultRoster(joinedAt: ts).first;
  }

  TeamConfig _normalizeTeam(TeamConfig team) {
    final hasLead = team.members.any(
      (m) => m.name == TeamMemberNaming.teamLeadName,
    );
    if (hasLead) return team;
    final now = DateTime.now().millisecondsSinceEpoch;
    return team.copyWith(
      members: [_defaultMember(now: now), ...team.members],
    );
  }

  TeamMemberConfig _normalizeMember(TeamMemberConfig member) {
    if (member.name == TeamMemberNaming.teamLeadName) return member;
    final slug = TeamMemberNaming.slugMemberName(member.name);
    return member.copyWith(name: slug);
  }

  String _uniqueMemberSlug(TeamConfig team, String base) {
    final existing = team.members.map((m) => m.name).toSet();
    final first = TeamMemberNaming.slugMemberName(base);
    if (!existing.contains(first)) return first;
    var i = 2;
    while (true) {
      final candidate = TeamMemberNaming.slugMemberName('$base-$i');
      if (!existing.contains(candidate)) return candidate;
      i++;
    }
  }
}
