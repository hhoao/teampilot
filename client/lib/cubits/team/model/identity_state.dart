import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';

import '../../../models/personal_identity.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace_identity.dart';

class IdentityState extends Equatable {
  const IdentityState({
    this.identities = const [],
    this.selectedTeamId,
    this.statusMessage = '',
    this.isLoading = true,
    this.isLaunching = false,
    this.isSyncingPlugins = false,
    this.pluginSyncConflicts = const {},
  });

  final List<WorkspaceIdentity> identities;
  final String? selectedTeamId;
  final String statusMessage;
  final bool isLoading;
  final bool isLaunching;
  final bool isSyncingPlugins;

  /// Plugin ids on the selected team that were linked under a fallback dir name.
  final Map<String, String> pluginSyncConflicts;

  List<TeamIdentity> get teams =>
      identities.whereType<TeamIdentity>().toList(growable: false);

  List<PersonalIdentity> get personals =>
      identities.whereType<PersonalIdentity>().toList(growable: false);

  WorkspaceIdentity? byId(String id) =>
      identities.where((e) => e.id == id).firstOrNull;

  TeamIdentity? get selectedTeam {
    for (final team in teams) {
      if (team.id == selectedTeamId) return team;
    }
    return teams.isEmpty ? null : teams.first;
  }

  IdentityState copyWith({
    List<WorkspaceIdentity>? identities,
    List<TeamIdentity>? teams,
    String? selectedTeamId,
    String? statusMessage,
    bool? isLoading,
    bool? isLaunching,
    bool? isSyncingPlugins,
    Map<String, String>? pluginSyncConflicts,
    bool clearSelectedTeamId = false,
  }) {
    final nextIdentities = identities ??
        (teams != null ? [...personals, ...teams] : this.identities);
    return IdentityState(
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
