import '../../models/app_session.dart';

/// Orders [teamIds] by the most-recent session for [projectId] whose
/// `sessionTeam` matches. Teams with no matching session keep their original
/// relative order, after all used teams.
List<String> orderTeamIdsByRecentUse({
  required String projectId,
  required List<String> teamIds,
  required List<AppSession> sessions,
}) {
  final lastUsed = <String, int>{};
  for (final s in sessions) {
    if (s.projectId != projectId) continue;
    final team = s.sessionTeam.trim();
    if (team.isEmpty) continue;
    final stamp = s.updatedAt != 0 ? s.updatedAt : s.createdAt;
    final existing = lastUsed[team];
    if (existing == null || stamp > existing) lastUsed[team] = stamp;
  }
  final indexed = [
    for (var i = 0; i < teamIds.length; i++) (i: i, id: teamIds[i]),
  ];
  indexed.sort((a, b) {
    final ua = lastUsed[a.id];
    final ub = lastUsed[b.id];
    if (ua != null && ub != null) return ub.compareTo(ua);
    if (ua != null) return -1;
    if (ub != null) return 1;
    return a.i.compareTo(b.i);
  });
  return [for (final e in indexed) e.id];
}
