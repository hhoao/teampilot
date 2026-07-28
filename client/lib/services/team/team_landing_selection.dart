import '../../models/discoverable_team.dart';
import '../../models/team_config.dart';
import 'team_clone_service.dart';

class TeamLandingResolveSuccess {
  const TeamLandingResolveSuccess({
    required this.teamId,
    this.cloneResult,
  });

  final String teamId;

  /// Non-null only when a fresh hub clone ran.
  final CloneResult? cloneResult;
}

class TeamLandingSelectionException implements Exception {
  TeamLandingSelectionException(this.message);
  final String message;

  @override
  String toString() => 'TeamLandingSelectionException: $message';
}

/// Shared earliest-match helper used by resolveHub and catalog mapping.
TeamProfile? earliestTeamWithHubSourceKey(
  List<TeamProfile> teams,
  String hubKey,
) {
  final key = hubKey.trim();
  if (key.isEmpty) return null;

  final matches = teams
      .where((team) => team.hubSourceKey == key)
      .toList(growable: false);
  if (matches.isEmpty) return null;

  matches.sort((a, b) {
    final byCreatedAt = a.createdAt.compareTo(b.createdAt);
    if (byCreatedAt != 0) return byCreatedAt;
    final bySortOrder = a.sortOrder.compareTo(b.sortOrder);
    if (bySortOrder != 0) return bySortOrder;
    return a.id.compareTo(b.id);
  });
  return matches.first;
}

class TeamLandingSelection {
  TeamLandingSelection({
    required Future<CloneResult> Function(DiscoverableTeam team) cloneTeam,
    required Future<void> Function(String teamId) touchRecent,
  }) : _cloneTeam = cloneTeam,
       _touchRecent = touchRecent;

  final Future<CloneResult> Function(DiscoverableTeam team) _cloneTeam;
  final Future<void> Function(String teamId) _touchRecent;

  Future<TeamLandingResolveSuccess> resolveLocal({
    required String teamId,
    required List<TeamProfile> teams,
  }) async {
    final id = teamId.trim();
    if (id.isEmpty || !teams.any((team) => team.id == id)) {
      throw TeamLandingSelectionException('team not found: "$teamId"');
    }

    await _touchRecent(id);
    return TeamLandingResolveSuccess(teamId: id);
  }

  Future<TeamLandingResolveSuccess> resolveHub({
    required DiscoverableTeam team,
    required List<TeamProfile> teams,
  }) async {
    final existing = earliestTeamWithHubSourceKey(teams, team.key);
    if (existing != null) {
      await _touchRecent(existing.id);
      return TeamLandingResolveSuccess(teamId: existing.id);
    }

    try {
      final result = await _cloneTeam(team);
      await _touchRecent(result.teamId);
      return TeamLandingResolveSuccess(
        teamId: result.teamId,
        cloneResult: result,
      );
    } on CloneException catch (e) {
      throw TeamLandingSelectionException(e.message);
    }
  }
}
