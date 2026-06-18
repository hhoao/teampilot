import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';

import '../../../models/personal_profile.dart';
import '../../../models/team_config.dart';
import '../../../models/launch_profile.dart';

class LaunchProfileState extends Equatable {
  const LaunchProfileState({
    this.identities = const [],
    this.selectedTeamId,
    this.statusMessage = '',
    this.isLoading = true,
    this.isLaunching = false,
    this.isSyncingPlugins = false,
    this.pluginSyncConflicts = const {},
  });

  final List<LaunchProfile> identities;
  final String? selectedTeamId;
  final String statusMessage;
  final bool isLoading;
  final bool isLaunching;
  final bool isSyncingPlugins;

  /// Plugin ids on the selected team that were linked under a fallback dir name.
  final Map<String, String> pluginSyncConflicts;

  List<TeamProfile> get teams =>
      identities.whereType<TeamProfile>().toList(growable: false);

  List<PersonalProfile> get personals =>
      identities.whereType<PersonalProfile>().toList(growable: false);

  LaunchProfile? byId(String id) =>
      identities.where((e) => e.id == id).firstOrNull;

  TeamProfile? get selectedTeam {
    for (final team in teams) {
      if (team.id == selectedTeamId) return team;
    }
    return teams.isEmpty ? null : teams.first;
  }

  LaunchProfileState copyWith({
    List<LaunchProfile>? identities,
    List<PersonalProfile>? personals,
    List<TeamProfile>? teams,
    String? selectedTeamId,
    String? statusMessage,
    bool? isLoading,
    bool? isLaunching,
    bool? isSyncingPlugins,
    Map<String, String>? pluginSyncConflicts,
    bool clearSelectedTeamId = false,
  }) {
    final nextIdentities = identities ??
        (personals != null
            ? [...personals, ...teams ?? this.teams]
            : teams != null
                ? [...this.personals, ...teams]
                : this.identities);
    return LaunchProfileState(
      identities: nextIdentities,
      selectedTeamId: clearSelectedTeamId
          ? null
          : (selectedTeamId ?? this.selectedTeamId),
      statusMessage: statusMessage ?? this.statusMessage,
      isLoading: isLoading ?? this.isLoading,
      isLaunching: isLaunching ?? this.isLaunching,
      isSyncingPlugins: isSyncingPlugins ?? this.isSyncingPlugins,
      pluginSyncConflicts: pluginSyncConflicts ?? this.pluginSyncConflicts,
    );
  }

  @override
  List<Object?> get props => [
        identities,
        selectedTeamId,
        statusMessage,
        isLoading,
        isLaunching,
        isSyncingPlugins,
        pluginSyncConflicts,
      ];
}
