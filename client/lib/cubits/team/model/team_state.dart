import 'package:equatable/equatable.dart';

import '../../../models/team_config.dart';

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
