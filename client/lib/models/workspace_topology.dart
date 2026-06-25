import 'member_instance.dart';
import 'runtime_target.dart';
import 'team_config.dart';
import 'workspace_folder.dart';
import '../utils/team_member_naming.dart';
import '../utils/workspace_path_utils.dart';

/// Mixed-workspace machine pin per runtime instance (instanceId → targetId).
typedef MemberTargetAssignments = Map<String, String>;

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

/// Resolves which machine owns [paths] in [folders] (file-tree / git panels).
String? targetIdForFolderPaths(
  List<WorkspaceFolder> folders,
  List<String> paths, {
  bool matchSubpaths = false,
}) {
  if (paths.isEmpty) return null;
  for (final raw in paths) {
    final path = raw.trim();
    if (path.isEmpty) continue;
    for (final f in folders) {
      if (workspacePathsEqual(f.path, path)) return f.targetId;
    }
  }
  if (!matchSubpaths) return null;
  for (final raw in paths) {
    final normalized = normalizeWorkspacePath(raw.trim());
    if (normalized.isEmpty) continue;
    WorkspaceFolder? best;
    var bestRootLen = -1;
    for (final f in folders) {
      final root = normalizeWorkspacePath(f.path);
      if (root.isEmpty) continue;
      if (normalized == root || normalized.startsWith('$root/')) {
        if (root.length > bestRootLen) {
          best = f;
          bestRootLen = root.length;
        }
      }
    }
    if (best != null) return best.targetId;
  }
  return null;
}

/// Workspace folders win on path collisions; session-only paths are appended.
List<WorkspaceFolder> mergeWorkspaceFolderCatalog({
  required List<WorkspaceFolder> sessionFolders,
  required List<WorkspaceFolder> workspaceFolders,
}) {
  if (workspaceFolders.isEmpty) return sessionFolders;
  final merged = <WorkspaceFolder>[...workspaceFolders];
  for (final sf in sessionFolders) {
    if (workspaceFolders.any((wf) => workspacePathsEqual(wf.path, sf.path))) {
      continue;
    }
    merged.add(sf);
  }
  return merged;
}

String? memberTargetForInstanceId(
  MemberTargetAssignments targets,
  String instanceId,
) {
  final trimmed = instanceId.trim();
  if (trimmed.isEmpty) return null;
  final targetId = targets[trimmed]?.trim();
  if (targetId == null || targetId.isEmpty) return null;
  return targetId;
}

/// Working directory + add-dirs for a member pinned to [targetId].
({String workingDirectory, List<String> addDirs}) memberWorkDirsForTarget(
  List<WorkspaceFolder> folders,
  String targetId,
) {
  final paths = folderPathsForTarget(folders, targetId.trim());
  if (paths.isEmpty) {
    return (workingDirectory: '', addDirs: const []);
  }
  return (
    workingDirectory: paths.first,
    addDirs: paths.skip(1).toList(growable: false),
  );
}

MemberPlacementByTarget memberPlacementFromMemberTargets({
  required List<TeamMemberConfig> members,
  required MemberTargetAssignments targets,
}) {
  final roster = [for (final m in members) if (m.isValid) m];
  final placement = <String, Map<String, int>>{};
  for (final instance in expandTeamRoster(roster)) {
    final targetId = memberTargetForInstanceId(targets, instance.instanceId);
    if (targetId == null) continue;
    final byType = placement.putIfAbsent(targetId, () => {});
    byType[instance.type.id] = (byType[instance.type.id] ?? 0) + 1;
  }
  return placement;
}

MemberTargetAssignments memberTargetsFromMemberPlacement({
  required List<WorkspaceFolder> workspaceFolders,
  required List<TeamMemberConfig> members,
  required MemberPlacementByTarget placement,
}) {
  final roster = [for (final m in members) if (m.isValid) m];
  final result = <String, String>{};
  for (final type in roster) {
    final instances = expandTeamRoster([type]);
    var index = 0;
    for (final targetId in workspaceTargetIds(workspaceFolders)) {
      final count = placement[targetId]?[type.id] ?? 0;
      if (count <= 0) continue;
      for (var i = 0; i < count && index < instances.length; i++, index++) {
        result[instances[index].instanceId] = targetId;
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

bool memberTargetsComplete({
  required List<WorkspaceFolder> workspaceFolders,
  required List<TeamMemberConfig> members,
  required MemberTargetAssignments targets,
}) {
  if (!workspaceTopologyRequiresMemberAssignment(workspaceFolders)) {
    return true;
  }
  final roster = [for (final m in members) if (m.isValid) m];
  for (final instance in expandTeamRoster(roster)) {
    final targetId = memberTargetForInstanceId(targets, instance.instanceId);
    if (targetId == null) return false;
    if (folderPathsForTarget(workspaceFolders, targetId).isEmpty) return false;
  }
  return true;
}

MemberTargetAssignments rememberedMemberTargets(
  Map<String, MemberTargetAssignments> byTeam,
  String teamId,
) {
  final remembered = byTeam[teamId.trim()];
  if (remembered == null || remembered.isEmpty) return const {};
  return Map.unmodifiable({
    for (final e in remembered.entries)
      if (e.key.trim().isNotEmpty && e.value.trim().isNotEmpty)
        e.key.trim(): e.value.trim(),
  });
}
