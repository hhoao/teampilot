import 'member_instance.dart';
import 'runtime_target.dart';
import 'team_config.dart';
import 'workspace_folder.dart';
import '../utils/team_member_naming.dart';
import '../utils/workspace_path_utils.dart';

/// Per-member folder paths keyed by roster member or runtime instance id.
typedef MemberFolderAssignments = Map<String, List<String>>;

/// Instance counts per roster member type on each workspace target.
typedef MemberPlacementByTarget = Map<String, Map<String, int>>;

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

/// Effective pool size for [type] (leader is always a singleton).
int memberTypeReplicaCount(TeamMemberConfig type) =>
    TeamMemberNaming.isTeamLead(type) || type.replicas < 1 ? 1 : type.replicas;

List<String> workspaceTargetIds(List<WorkspaceFolder> folders) {
  final seen = <String>[];
  for (final f in folders) {
    if (!seen.contains(f.targetId)) seen.add(f.targetId);
  }
  return seen;
}

List<String> folderPathsForTarget(
  List<WorkspaceFolder> folders,
  String targetId,
) => [
  for (final f in folders)
    if (f.targetId == targetId) f.path,
];

String? targetIdForFolderPaths(
  List<WorkspaceFolder> folders,
  List<String> paths,
) {
  if (paths.isEmpty) return null;
  final first = paths.first.trim();
  for (final f in folders) {
    if (workspacePathsEqual(f.path, first)) return f.targetId;
  }
  return null;
}

List<String>? folderAssignmentForInstance(
  MemberFolderAssignments assignments,
  MemberInstance instance,
) {
  final direct = assignments[instance.instanceId];
  if (direct != null && direct.isNotEmpty) return direct;
  final legacy = assignments[instance.type.id];
  if (legacy != null && legacy.isNotEmpty) return legacy;
  return null;
}

MemberPlacementByTarget memberPlacementFromFolderAssignments({
  required List<WorkspaceFolder> workspaceFolders,
  required List<TeamMemberConfig> members,
  required MemberFolderAssignments assignments,
}) {
  final roster = [for (final m in members) if (m.isValid) m];
  final placement = <String, Map<String, int>>{
    for (final id in workspaceTargetIds(workspaceFolders)) id: {},
  };
  for (final instance in expandTeamRoster(roster)) {
    final paths = folderAssignmentForInstance(assignments, instance);
    if (paths == null || paths.isEmpty) continue;
    final targetId = targetIdForFolderPaths(workspaceFolders, paths);
    if (targetId == null) continue;
    final byType = placement.putIfAbsent(targetId, () => {});
    byType[instance.type.id] = (byType[instance.type.id] ?? 0) + 1;
  }
  return placement;
}

MemberFolderAssignments folderAssignmentsFromMemberPlacement({
  required List<WorkspaceFolder> workspaceFolders,
  required List<TeamMemberConfig> members,
  required MemberPlacementByTarget placement,
}) {
  final roster = [for (final m in members) if (m.isValid) m];
  final result = <String, List<String>>{};
  for (final type in roster) {
    final instances = expandTeamRoster([type]);
    var index = 0;
    for (final targetId in workspaceTargetIds(workspaceFolders)) {
      final count = placement[targetId]?[type.id] ?? 0;
      final paths = folderPathsForTarget(workspaceFolders, targetId);
      if (paths.isEmpty) continue;
      for (var i = 0; i < count && index < instances.length; i++, index++) {
        result[instances[index].instanceId] = paths;
      }
    }
  }
  return result;
}

int memberPlacementCountForType(
  MemberPlacementByTarget placement,
  String memberTypeId,
) {
  var total = 0;
  for (final counts in placement.values) {
    total += counts[memberTypeId] ?? 0;
  }
  return total;
}

bool memberPlacementComplete({
  required List<WorkspaceFolder> workspaceFolders,
  required List<TeamMemberConfig> members,
  required MemberPlacementByTarget placement,
}) {
  if (!workspaceTopologyRequiresMemberAssignment(workspaceFolders)) {
    return true;
  }
  for (final type in members) {
    if (!type.isValid) continue;
    final needed = memberTypeReplicaCount(type);
    if (memberPlacementCountForType(placement, type.id) != needed) {
      return false;
    }
  }
  return true;
}

bool memberFolderAssignmentsComplete({
  required List<WorkspaceFolder> workspaceFolders,
  required List<TeamMemberConfig> members,
  required MemberFolderAssignments assignments,
}) {
  if (!workspaceTopologyRequiresMemberAssignment(workspaceFolders)) {
    return true;
  }
  final roster = [for (final m in members) if (m.isValid) m];
  for (final instance in expandTeamRoster(roster)) {
    final paths = folderAssignmentForInstance(assignments, instance);
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
