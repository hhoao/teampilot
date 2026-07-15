import '../../models/app_session.dart';
import '../../models/workspace_folder.dart';
import '../../models/workspace_topology.dart';

class WorkspaceTargetRemapResult {
  const WorkspaceTargetRemapResult({
    required this.folders,
    required this.memberTargetsByTeam,
    required this.sessions,
  });

  final List<WorkspaceFolder> folders;
  final Map<String, MemberTargetAssignments> memberTargetsByTeam;
  final List<AppSession> sessions;
}

abstract final class WorkspaceTargetRemap {
  static bool usesTarget({
    required List<WorkspaceFolder> folders,
    required Map<String, MemberTargetAssignments> memberTargetsByTeam,
    required List<AppSession> sessions,
    required String targetId,
  }) {
    final id = targetId.trim();
    if (id.isEmpty) return false;
    if (folders.any((f) => f.targetId == id)) return true;
    for (final pins in memberTargetsByTeam.values) {
      if (pins.values.any((v) => v == id)) return true;
    }
    for (final s in sessions) {
      if (s.folders.any((f) => f.targetId == id)) return true;
      if (s.memberTargets.values.any((v) => v == id)) return true;
    }
    return false;
  }

  static WorkspaceTargetRemapResult apply({
    required List<WorkspaceFolder> folders,
    required Map<String, MemberTargetAssignments> memberTargetsByTeam,
    required List<AppSession> sessions,
    required String fromTargetId,
    required String toTargetId,
  }) {
    final from = fromTargetId.trim();
    final to = toTargetId.trim();
    if (from.isEmpty || to.isEmpty) {
      throw ArgumentError('fromTargetId and toTargetId must be non-empty');
    }
    if (from == to) {
      return WorkspaceTargetRemapResult(
        folders: folders,
        memberTargetsByTeam: memberTargetsByTeam,
        sessions: const [],
      );
    }

    final nextFolders = [
      for (final f in folders)
        f.targetId == from ? f.copyWith(targetId: to) : f,
    ];

    final nextPins = <String, MemberTargetAssignments>{};
    for (final e in memberTargetsByTeam.entries) {
      nextPins[e.key] = {
        for (final p in e.value.entries)
          p.key: p.value == from ? to : p.value,
      };
    }

    final changedSessions = <AppSession>[];
    for (final s in sessions) {
      final folderHit = s.folders.any((f) => f.targetId == from);
      final pinHit = s.memberTargets.values.any((v) => v == from);
      if (!folderHit && !pinHit) continue;
      changedSessions.add(
        s.copyWith(
          folders: [
            for (final f in s.folders)
              f.targetId == from ? f.copyWith(targetId: to) : f,
          ],
          memberTargets: {
            for (final p in s.memberTargets.entries)
              p.key: p.value == from ? to : p.value,
          },
        ),
      );
    }

    return WorkspaceTargetRemapResult(
      folders: nextFolders,
      memberTargetsByTeam: nextPins,
      sessions: changedSessions,
    );
  }
}
