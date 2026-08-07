import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';

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
  });

  final List<LaunchProfile> identities;
  final String? selectedTeamId;
  final String statusMessage;
  final bool isLoading;
  final bool isLaunching;
  final bool isSyncingPlugins;

  List<TeamProfile> get teams =>
      identities.whereType<TeamProfile>().toList(growable: false);

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
    List<TeamProfile>? teams,
    String? selectedTeamId,
    String? statusMessage,
    bool? isLoading,
    bool? isLaunching,
    bool? isSyncingPlugins,
    bool clearSelectedTeamId = false,
  }) {
    final nextIdentities =
        identities ??
        (teams != null ? List<LaunchProfile>.from(teams) : this.identities);
    return LaunchProfileState(
      identities: nextIdentities,
      selectedTeamId: clearSelectedTeamId
          ? null
          : (selectedTeamId ?? this.selectedTeamId),
      statusMessage: statusMessage ?? this.statusMessage,
      isLoading: isLoading ?? this.isLoading,
      isLaunching: isLaunching ?? this.isLaunching,
      isSyncingPlugins: isSyncingPlugins ?? this.isSyncingPlugins,
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
  ];
}
