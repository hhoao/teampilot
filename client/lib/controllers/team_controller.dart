import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/launch_command_builder.dart';
import '../models/team_config.dart';
import '../repositories/team_repository.dart';

typedef TeamLauncher =
    Future<void> Function(TeamConfig team, TeamMemberConfig member);
typedef StringProvider = String Function();

class TeamController extends ChangeNotifier {
  TeamController({
    required TeamRepository repository,
    TeamLauncher? launcher,
    StringProvider? currentDirectoryProvider,
    StringProvider? idProvider,
  }) : _repository = repository,
       _launcher =
           launcher ??
           ((team, member) =>
               LaunchCommandBuilder.launch(team, member: member)),
       _currentDirectoryProvider =
           currentDirectoryProvider ?? (() => Directory.current.path),
       _idProvider =
           idProvider ??
           (() => DateTime.now().microsecondsSinceEpoch.toString());

  final TeamRepository _repository;
  final TeamLauncher _launcher;
  final StringProvider _currentDirectoryProvider;
  final StringProvider _idProvider;

  var _teams = <TeamConfig>[];
  String? _selectedTeamId;
  String _statusMessage = '';
  bool _isLoading = true;
  bool _isLaunching = false;

  List<TeamConfig> get teams => List.unmodifiable(_teams);
  String get statusMessage => _statusMessage;
  bool get isLoading => _isLoading;
  bool get isLaunching => _isLaunching;

  TeamConfig? get selectedTeam {
    for (final team in _teams) {
      if (team.id == _selectedTeamId) {
        return team;
      }
    }
    return _teams.isEmpty ? null : _teams.first;
  }

  String previewFor(TeamMemberConfig member) {
    final team = selectedTeam;
    return team == null ? '' : LaunchCommandBuilder.preview(team, member);
  }

  String get selectedCommandPreview {
    final team = selectedTeam;
    if (team == null || team.members.isEmpty) {
      return '';
    }
    return LaunchCommandBuilder.preview(team, team.members.first);
  }

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    _teams = await _repository.loadTeams();
    if (_teams.isEmpty) {
      _teams = [_defaultTeam()];
      await _repository.saveTeams(_teams);
    }
    _selectedTeamId = _teams.first.id;
    _isLoading = false;
    _statusMessage = 'Ready.';
    notifyListeners();
  }

  void selectTeam(String id) {
    if (_teams.any((team) => team.id == id)) {
      _selectedTeamId = id;
      _statusMessage = 'Selected ${selectedTeam?.name ?? 'team'}.';
      notifyListeners();
    }
  }

  Future<void> addTeam() async {
    final team = TeamConfig(
      id: _idProvider(),
      name: 'New Team',
      workingDirectory: _currentDirectoryProvider(),
      members: [TeamMemberConfig(id: _idProvider(), name: 'New Member')],
    );
    _teams = [..._teams, team];
    _selectedTeamId = team.id;
    _statusMessage = 'Added ${team.name}.';
    await _repository.saveTeams(_teams);
    notifyListeners();
  }

  Future<void> updateSelected(TeamConfig updated) async {
    final selected = selectedTeam;
    if (selected == null) {
      return;
    }
    final normalized = updated.members.isEmpty
        ? updated.copyWith(members: [_defaultMember()])
        : updated;
    _teams = [
      for (final team in _teams)
        if (team.id == selected.id) normalized else team,
    ];
    _selectedTeamId = normalized.id;
    _statusMessage = normalized.isValid
        ? 'Saved ${normalized.name}.'
        : 'Team name and directory are required.';
    await _repository.saveTeams(_teams);
    notifyListeners();
  }

  Future<void> deleteSelected() async {
    final selected = selectedTeam;
    if (selected == null) {
      return;
    }
    _teams = _teams.where((team) => team.id != selected.id).toList();
    if (_teams.isEmpty) {
      _teams = [_defaultTeam()];
    }
    _selectedTeamId = _teams.first.id;
    _statusMessage = 'Deleted ${selected.name}.';
    await _repository.saveTeams(_teams);
    notifyListeners();
  }

  Future<void> addMember() async {
    final team = selectedTeam;
    if (team == null) {
      return;
    }
    final member = TeamMemberConfig(id: _idProvider(), name: 'New Member');
    await updateSelected(team.copyWith(members: [...team.members, member]));
    _statusMessage = 'Added ${member.name}.';
    notifyListeners();
  }

  Future<void> updateMember(String memberId, TeamMemberConfig updated) async {
    final team = selectedTeam;
    if (team == null) {
      return;
    }
    await updateSelected(
      team.copyWith(
        members: [
          for (final member in team.members)
            if (member.id == memberId) updated else member,
        ],
      ),
    );
  }

  Future<void> deleteMember(String memberId) async {
    final team = selectedTeam;
    if (team == null) {
      return;
    }
    if (team.members.length == 1) {
      _statusMessage = 'A team needs at least one member.';
      notifyListeners();
      return;
    }
    final deleted = team.members.firstWhere((member) => member.id == memberId);
    await updateSelected(
      team.copyWith(
        members: team.members
            .where((member) => member.id != memberId)
            .toList(growable: false),
      ),
    );
    _statusMessage = 'Deleted ${deleted.name}.';
    notifyListeners();
  }

  Future<void> launchMember(String memberId) async {
    final team = selectedTeam;
    if (team == null || !team.isValid) {
      _statusMessage = 'Team name and directory are required.';
      notifyListeners();
      return;
    }
    final member = team.members.firstWhere(
      (item) => item.id == memberId,
      orElse: () => const TeamMemberConfig(id: '', name: ''),
    );
    if (!member.isValid) {
      _statusMessage = 'Member name is required.';
      notifyListeners();
      return;
    }

    _isLaunching = true;
    _statusMessage = 'Starting ${member.name}...';
    notifyListeners();

    try {
      await _launcher(team, member);
      _statusMessage =
          'Started ${member.name}: ${LaunchCommandBuilder.preview(team, member)}';
    } on Object catch (error) {
      _statusMessage = 'Launch failed: $error';
    } finally {
      _isLaunching = false;
      notifyListeners();
    }
  }

  Future<void> launchSelectedTeam() async {
    final team = selectedTeam;
    if (team == null || !team.isValid) {
      _statusMessage = 'Team name and directory are required.';
      notifyListeners();
      return;
    }
    final validMembers = team.members
        .where((member) => member.isValid)
        .toList();
    if (validMembers.isEmpty) {
      _statusMessage = 'At least one valid member is required.';
      notifyListeners();
      return;
    }

    _isLaunching = true;
    _statusMessage = 'Starting ${validMembers.length} members...';
    notifyListeners();

    try {
      for (final member in validMembers) {
        await _launcher(team, member);
      }
      _statusMessage = 'Started ${validMembers.length} members.';
    } on Object catch (error) {
      _statusMessage = 'Launch failed: $error';
    } finally {
      _isLaunching = false;
      notifyListeners();
    }
  }

  TeamConfig _defaultTeam() {
    return TeamConfig(
      id: 'default',
      name: 'Default Team',
      workingDirectory: _currentDirectoryProvider(),
      members: [_defaultMember()],
    );
  }

  TeamMemberConfig _defaultMember() {
    return const TeamMemberConfig(id: 'team-lead', name: 'team-lead');
  }
}
