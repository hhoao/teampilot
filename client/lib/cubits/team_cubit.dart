import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/skill.dart';
import '../models/team_config.dart';
import '../repositories/team_repository.dart';
import '../services/launch_command_builder.dart';
import '../services/team_skill_linker_service.dart';
import '../utils/logger.dart';

class TeamState extends Equatable {
  const TeamState({
    this.teams = const [],
    this.selectedTeamId,
    this.statusMessage = '',
    this.isLoading = true,
    this.isLaunching = false,
    this.isSyncingSkills = false,
  });

  final List<TeamConfig> teams;
  final String? selectedTeamId;
  final String statusMessage;
  final bool isLoading;
  final bool isLaunching;
  final bool isSyncingSkills;

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
    bool clearSelectedTeamId = false,
  }) {
    return TeamState(
      teams: teams ?? this.teams,
      selectedTeamId:
          clearSelectedTeamId ? null : (selectedTeamId ?? this.selectedTeamId),
      statusMessage: statusMessage ?? this.statusMessage,
      isLoading: isLoading ?? this.isLoading,
      isLaunching: isLaunching ?? this.isLaunching,
      isSyncingSkills: isSyncingSkills ?? this.isSyncingSkills,
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
      ];
}

typedef TeamLauncher = Future<void> Function(
    TeamConfig team, TeamMemberConfig member);
typedef StringProvider = String Function();
typedef InstalledSkillsLoader = Future<List<Skill>> Function();

class TeamCubit extends Cubit<TeamState> {
  TeamCubit({
    required TeamRepository repository,
    required String Function() executableResolver,
    TeamLauncher? launcher,
    String? Function()? llmConfigPathOverride,
    TeamSkillLinkerService? skillLinker,
    InstalledSkillsLoader? installedSkillsLoader,
  })  : _repository = repository,
        _executableResolver = executableResolver,
        _llmConfigPathOverride = llmConfigPathOverride,
        _skillLinker = skillLinker ?? TeamSkillLinkerService(),
        _installedSkillsLoader = installedSkillsLoader,
        _launcher = launcher ??
            ((team, member) => LaunchCommandBuilder.launch(team,
                member: member,
                executable: executableResolver(),
                extraEnvironment:
                    _envFromOverride(llmConfigPathOverride?.call()))),
        super(const TeamState());

  final TeamRepository _repository;
  final TeamLauncher _launcher;
  final String Function() _executableResolver;
  // ignore: unused_field
  final String? Function()? _llmConfigPathOverride;
  final TeamSkillLinkerService _skillLinker;
  final InstalledSkillsLoader? _installedSkillsLoader;

  static Map<String, String>? _envFromOverride(String? override) {
    if (override == null || override.isEmpty) return null;
    return {'LLM_CONFIG_PATH': override};
  }

  String previewFor(TeamMemberConfig member) {
    final team = state.selectedTeam;
    return team == null
        ? ''
        : LaunchCommandBuilder.preview(
            team,
            member,
            executable: _executableResolver(),
          );
  }

  String get selectedCommandPreview {
    final team = state.selectedTeam;
    if (team == null || team.members.isEmpty) return '';
    return LaunchCommandBuilder.preview(
      team,
      team.members.first,
      executable: _executableResolver(),
    );
  }

  Future<void> load() async {
    appLogger.i('TeamCubit loading teams...');
    emit(state.copyWith(isLoading: true));
    var teams = await _repository.loadTeams();
    if (teams.isEmpty) {
      teams = [_defaultTeam()];
      await _repository.saveTeams(teams);
    }
    emit(state.copyWith(
      teams: teams,
      selectedTeamId: teams.first.id,
      isLoading: false,
      statusMessage: 'Ready.',
    ));
    appLogger.i('TeamCubit loaded ${teams.length} teams');
  }

  Future<void> selectTeam(String id) async {
    if (!state.teams.any((team) => team.id == id)) return;
    final team = state.teams.firstWhere((t) => t.id == id);
    emit(state.copyWith(
        selectedTeamId: id, statusMessage: 'Selected ${team.name}.'));
    await _syncSkillsForSelected();
  }

  Future<void> syncSelectedTeamSkills({List<Skill>? installed}) async {
    await _syncSkillsForSelected(installed: installed);
  }

  Future<void> removeSkillFromAllTeams(String skillId) async {
    final selected = state.selectedTeam;
    final syncNeeded =
        selected != null && selected.skillIds.contains(skillId);
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

    emit(state.copyWith(isSyncingSkills: true));
    try {
      final List<Skill> catalog;
      if (installed != null) {
        catalog = installed;
      } else {
        catalog = await (_installedSkillsLoader?.call() ??
            Future.value(const <Skill>[]));
      }
      final enabled = catalog.where((s) => s.enabled).toList(growable: false);

      var result = await _skillLinker.syncForTeam(
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
          emit(state.copyWith(teams: teams));
          await _repository.saveTeams(teams);
          result = await _skillLinker.syncForTeam(
            skillIds: prunedIds,
            installed: enabled,
          );
        }
      }

      var status = state.statusMessage;
      if (result.linked.isNotEmpty) {
        status =
            'Linked ${result.linked.length} skill(s) for ${team.name}.';
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
      emit(state.copyWith(statusMessage: status));
    } catch (e) {
      appLogger.e('[team-skills] sync failed: $e');
      emit(state.copyWith(statusMessage: 'Skill sync failed: $e'));
    } finally {
      emit(state.copyWith(isSyncingSkills: false));
    }
  }

  Future<void> addTeam() async {
    final name = _uniqueTeamName('New Team');
    final memberName = 'team-lead';
    final team = TeamConfig(
      id: name,
      name: name,
      members: [TeamMemberConfig(id: memberName, name: memberName)],
    );
    final teams = [...state.teams, team];
    emit(state.copyWith(
        teams: teams,
        selectedTeamId: team.id,
        statusMessage: 'Added ${team.name}.'));
    await _repository.saveTeams(teams);
    await _syncSkillsForSelected();
  }

  Future<void> updateSelected(TeamConfig updated) async {
    final selected = state.selectedTeam;
    if (selected == null) return;
    final skillsChanged = !listEquals(selected.skillIds, updated.skillIds);
    final normalized = updated.members.isEmpty
        ? updated.copyWith(members: [_defaultMember()])
        : updated;
    final teams = [
      for (final team in state.teams)
        if (team.id == selected.id) normalized else team,
    ];
    emit(state.copyWith(
      teams: teams,
      selectedTeamId: normalized.id,
      statusMessage: normalized.isValid
          ? 'Saved ${normalized.name}.'
          : 'Name is required.',
    ));
    await _repository.saveTeams(teams);
    if (skillsChanged) {
      await _syncSkillsForSelected();
    }
  }

  Future<void> deleteSelected() async {
    final selected = state.selectedTeam;
    if (selected == null) return;
    await _repository.deleteTeam(selected.name);
    var teams =
        state.teams.where((team) => team.id != selected.id).toList();
    if (teams.isEmpty) teams = [_defaultTeam()];
    emit(state.copyWith(
        teams: teams,
        selectedTeamId: teams.first.id,
        statusMessage: 'Deleted ${selected.name}.'));
    await _repository.saveTeams(teams);
    await _syncSkillsForSelected();
  }

  Future<void> addMember() async {
    final team = state.selectedTeam;
    if (team == null) return;
    final name = _uniqueMemberName(team, 'New Member');
    final member = TeamMemberConfig(id: name, name: name);
    await updateSelected(
        team.copyWith(members: [...team.members, member]));
    emit(state.copyWith(statusMessage: 'Added ${member.name}.'));
  }

  Future<void> updateMember(
      String memberId, TeamMemberConfig updated) async {
    final team = state.selectedTeam;
    if (team == null) return;
    await updateSelected(team.copyWith(members: [
      for (final m in team.members)
        if (m.id == memberId) updated else m,
    ]));
  }

  Future<void> deleteMember(String memberId) async {
    final team = state.selectedTeam;
    if (team == null) return;
    if (team.members.length == 1) {
      emit(state.copyWith(
          statusMessage: 'A team needs at least one member.'));
      return;
    }
    final deleted =
        team.members.firstWhere((m) => m.id == memberId);
    await updateSelected(team.copyWith(
      members: team.members
          .where((m) => m.id != memberId)
          .toList(growable: false),
    ));
    emit(state.copyWith(statusMessage: 'Deleted ${deleted.name}.'));
  }

  Future<void> launchMember(String memberId) async {
    final team = state.selectedTeam;
    if (team == null || team.name.trim().isEmpty) {
      emit(state.copyWith(
          statusMessage: 'Team name is required.'));
      return;
    }
    final member = team.members.firstWhere((m) => m.id == memberId,
        orElse: () => const TeamMemberConfig(id: '', name: ''));
    if (!member.isValid) {
      emit(state.copyWith(statusMessage: 'Member name is required.'));
      return;
    }
    emit(state.copyWith(
        isLaunching: true, statusMessage: 'Starting ${member.name}...'));
    try {
      await _launcher(team, member);
      emit(state.copyWith(
          isLaunching: false,
          statusMessage:
              'Started ${member.name}: ${LaunchCommandBuilder.preview(team, member, executable: _executableResolver())}'));
    } on Object catch (error) {
      emit(state.copyWith(
          isLaunching: false, statusMessage: 'Launch failed: $error'));
    }
  }

  Future<void> launchSelectedTeam() async {
    final team = state.selectedTeam;
    if (team == null || team.name.trim().isEmpty) {
      emit(state.copyWith(
          statusMessage: 'Team name is required.'));
      return;
    }
    final validMembers =
        team.members.where((m) => m.isValid).toList();
    if (validMembers.isEmpty) {
      emit(state.copyWith(
          statusMessage: 'At least one valid member is required.'));
      return;
    }
    emit(state.copyWith(
        isLaunching: true,
        statusMessage: 'Starting ${validMembers.length} members...'));
    try {
      for (final member in validMembers) {
        await _launcher(team, member);
      }
      emit(state.copyWith(
          isLaunching: false,
          statusMessage: 'Started ${validMembers.length} members.'));
    } on Object catch (error) {
      emit(state.copyWith(
          isLaunching: false, statusMessage: 'Launch failed: $error'));
    }
  }

  TeamConfig _defaultTeam() {
    const name = 'Default Team';
    return TeamConfig(
      id: name,
      name: name,
      members: [_defaultMember()],
    );
  }

  TeamMemberConfig _defaultMember() =>
      const TeamMemberConfig(id: 'team-lead', name: 'team-lead');

  String _uniqueTeamName(String base) {
    final existing = state.teams.map((t) => t.name).toSet();
    if (!existing.contains(base)) return base;
    var i = 2;
    while (existing.contains('$base $i')) {
      i++;
    }
    return '$base $i';
  }

  String _uniqueMemberName(TeamConfig team, String base) {
    final existing = team.members.map((m) => m.name).toSet();
    if (!existing.contains(base)) return base;
    var i = 2;
    while (existing.contains('$base $i')) {
      i++;
    }
    return '$base $i';
  }
}
