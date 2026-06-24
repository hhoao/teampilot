import 'runtime_target.dart';
import 'team_config.dart';
import 'workspace_folder.dart';
import '../utils/workspace_path_utils.dart';

/// Per-member folder paths keyed by roster member id.
typedef MemberFolderAssignments = Map<String, List<String>>;

/// Emergent workspace shape from [WorkspaceFolder.targetId] uniformity (§4).
enum WorkspaceTopology {
  /// Every folder is [WorkspaceFolder.localTargetId].
  local,

  /// All folders share one non-local target (ssh / wsl).
  remote,

  /// Folders span more than one target.
  mixed,
}

/// Classifies [folders] for UI badges and member-assignment hints.
WorkspaceTopology workspaceTopologyOf(List<WorkspaceFolder> folders) {
  if (folders.isEmpty) return WorkspaceTopology.local;
  final ids = {for (final f in folders) f.targetId};
  if (ids.length > 1) return WorkspaceTopology.mixed;
  final id = ids.single;
  if (id == WorkspaceFolder.localTargetId) return WorkspaceTopology.local;
  return WorkspaceTopology.remote;
}

bool workspaceFolderIsRemote(String targetId) =>
    runtimeKindOfId(targetId) == RuntimeKind.ssh;

/// Personal identity cannot launch sessions on a mixed (cross-machine) workspace.
bool personalIdentityBlockedForWorkspace({
  required bool isPersonal,
  required List<WorkspaceFolder> folders,
}) =>
    isPersonal && workspaceTopologyRequiresMemberAssignment(folders);

/// Mixed workspaces need each roster member pinned to one machine's folders.
bool workspaceTopologyRequiresMemberAssignment(List<WorkspaceFolder> folders) =>
    workspaceTopologyOf(folders) == WorkspaceTopology.mixed;

bool memberFolderAssignmentsComplete({
  required List<WorkspaceFolder> workspaceFolders,
  required List<TeamMemberConfig> members,
  required MemberFolderAssignments assignments,
}) {
  if (!workspaceTopologyRequiresMemberAssignment(workspaceFolders)) {
    return true;
  }
  for (final member in members) {
    if (!member.isValid) continue;
    final paths = assignments[member.id];
    if (paths == null || paths.isEmpty) return false;
    if (!_assignmentPathsValid(workspaceFolders, paths)) return false;
  }
  return true;
}

bool _assignmentPathsValid(
  List<WorkspaceFolder> workspaceFolders,
  List<String> paths,
) {
  if (paths.isEmpty) return false;
  final first = paths.first.trim();
  if (first.isEmpty) return false;
  return workspaceFolders.any(
    (f) => workspacePathsEqual(f.path, first),
  );
}

MemberFolderAssignments rememberedMemberFolderAssignments(
  Map<String, MemberFolderAssignments> byTeam,
  String teamId,
) {
  final remembered = byTeam[teamId.trim()];
  if (remembered == null || remembered.isEmpty) return const {};
  return Map.unmodifiable({
    for (final e in remembered.entries)
      if (e.key.trim().isNotEmpty && e.value.isNotEmpty)
        e.key: List<String>.unmodifiable(e.value),
  });
}
