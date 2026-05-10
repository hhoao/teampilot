import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/team_config.dart';
import '../repositories/team_repository.dart';
import '../services/launch_command_builder.dart';

class TeamState extends Equatable {
  const TeamState({
    this.teams = const [],
    this.selectedTeamId,
    this.statusMessage = '',
    this.isLoading = true,
    this.isLaunching = false,
  });

  final List<TeamConfig> teams;
  final String? selectedTeamId;
  final String statusMessage;
  final bool isLoading;
  final bool isLaunching;

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
    bool clearSelectedTeamId = false,
  }) {
    return TeamState(
      teams: teams ?? this.teams,
      selectedTeamId:
          clearSelectedTeamId ? null : (selectedTeamId ?? this.selectedTeamId),
      statusMessage: statusMessage ?? this.statusMessage,
      isLoading: isLoading ?? this.isLoading,
      isLaunching: isLaunching ?? this.isLaunching,
    );
  }

  @override
  List<Object?> get props =>
      [teams, selectedTeamId, statusMessage, isLoading, isLaunching];
}

typedef TeamLauncher = Future<void> Function(
    TeamConfig team, TeamMemberConfig member);
typedef StringProvider = String Function();

class TeamCubit extends Cubit<TeamState> {
  TeamCubit({
    required TeamRepository repository,
    TeamLauncher? launcher,
    StringProvider? currentDirectoryProvider,
    StringProvider? idProvider,
  })  : _repository = repository,
        _launcher = launcher ??
            ((team, member) =>
                LaunchCommandBuilder.launch(team, member: member)),
        _currentDirectoryProvider =
            currentDirectoryProvider ?? (() => Directory.current.path),
        _idProvider = idProvider ??
            (() => DateTime.now().microsecondsSinceEpoch.toString()),
        super(const TeamState());

  final TeamRepository _repository;
  final TeamLauncher _launcher;
  final StringProvider _currentDirectoryProvider;
  final StringProvider _idProvider;

  String previewFor(TeamMemberConfig member) {
    final team = state.selectedTeam;
    return team == null ? '' : LaunchCommandBuilder.preview(team, member);
  }

  String get selectedCommandPreview {
    final team = state.selectedTeam;
    if (team == null || team.members.isEmpty) return '';
    return LaunchCommandBuilder.preview(team, team.members.first);
  }

  Future<void> load() async {
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
  }

  void selectTeam(String id) {
    if (state.teams.any((team) => team.id == id)) {
      final team = state.teams.firstWhere((t) => t.id == id);
      emit(state.copyWith(
          selectedTeamId: id, statusMessage: 'Selected ${team.name}.'));
    }
  }

  Future<void> addTeam() async {
    final team = TeamConfig(
      id: _idProvider(),
      name: 'New Team',
      workingDirectory: _currentDirectoryProvider(),
      members: [TeamMemberConfig(id: _idProvider(), name: 'New Member')],
    );
    final teams = [...state.teams, team];
    emit(state.copyWith(
        teams: teams,
        selectedTeamId: team.id,
        statusMessage: 'Added ${team.name}.'));
    await _repository.saveTeams(teams);
  }

  Future<void> updateSelected(TeamConfig updated) async {
    final selected = state.selectedTeam;
    if (selected == null) return;
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
          : 'Team name and directory are required.',
    ));
    await _repository.saveTeams(teams);
  }

  Future<void> deleteSelected() async {
    final selected = state.selectedTeam;
    if (selected == null) return;
    var teams =
        state.teams.where((team) => team.id != selected.id).toList();
    if (teams.isEmpty) teams = [_defaultTeam()];
    emit(state.copyWith(
        teams: teams,
        selectedTeamId: teams.first.id,
        statusMessage: 'Deleted ${selected.name}.'));
    await _repository.saveTeams(teams);
  }

  Future<void> addMember() async {
    final team = state.selectedTeam;
    if (team == null) return;
    final member = TeamMemberConfig(id: _idProvider(), name: 'New Member');
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
    if (team == null || !team.isValid) {
      emit(state.copyWith(
          statusMessage: 'Team name and directory are required.'));
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
              'Started ${member.name}: ${LaunchCommandBuilder.preview(team, member)}'));
    } on Object catch (error) {
      emit(state.copyWith(
          isLaunching: false, statusMessage: 'Launch failed: $error'));
    }
  }

  Future<void> launchSelectedTeam() async {
    final team = state.selectedTeam;
    if (team == null || !team.isValid) {
      emit(state.copyWith(
          statusMessage: 'Team name and directory are required.'));
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

  TeamConfig _defaultTeam() => TeamConfig(
        id: 'default',
        name: 'Default Team',
        workingDirectory: _currentDirectoryProvider(),
        members: [_defaultMember()],
      );

  TeamMemberConfig _defaultMember() =>
      const TeamMemberConfig(id: 'team-lead', name: 'team-lead');
}
