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

/// Mixed workspaces need each roster member pinned to one machine's folders.
bool workspaceTopologyRequiresMemberAssignment(List<WorkspaceFolder> folders) =>
    workspaceTopologyOf(folders) == WorkspaceTopology.mixed;

/// Effective pool size for [type] (leader is always a singleton).
int memberTypeReplicaCount(TeamMemberConfig type) {
  if (TeamMemberNaming.isTeamLead(type)) return 1;
  return type.replicas < 0 ? 0 : type.replicas;
}

/// Preferred host for the team lead: local when present, else first target.
String? preferredLeadHost(List<WorkspaceFolder> folders) {
  final ids = workspaceTargetIds(folders);
  if (ids.isEmpty) return null;
  if (ids.contains(WorkspaceFolder.localTargetId)) {
    return WorkspaceFolder.localTargetId;
  }
  return ids.first;
}

/// Default Machines placement when remembered targets are empty.
///
/// local/remote: each valid member type count `1` on the sole/preferred host.
/// mixed: lead `1` on preferred lead host; other types start at `0`.
MemberPlacementByTarget defaultMemberPlacement({
  required List<WorkspaceFolder> folders,
  required List<TeamMemberConfig> members,
}) {
  final host = preferredLeadHost(folders);
  if (host == null) return const {};
  final roster = [
    for (final m in members)
      if (m.isValid) m,
  ];
  if (roster.isEmpty) return const {};

  final byType = <String, int>{};
  final mixed = workspaceTopologyOf(folders) == WorkspaceTopology.mixed;
  for (final type in roster) {
    if (TeamMemberNaming.isTeamLead(type)) {
      byType[type.id] = 1;
    } else if (!mixed) {
      byType[type.id] = 1;
    }
  }
  if (byType.isEmpty) return const {};
  return {host: byType};
}

/// Whether the lead instance is pinned to a valid preferred host.
///
/// Returns true when no lead member is present. When a local folder exists,
/// lead must be on local; otherwise lead must be on a folder-backed target.
bool leadPlacementValid({
  required List<WorkspaceFolder> folders,
  required List<TeamMemberConfig> members,
  required MemberTargetAssignments targets,
}) {
  TeamMemberConfig? lead;
  for (final m in members) {
    if (m.isValid && TeamMemberNaming.isTeamLead(m)) {
      lead = m;
      break;
    }
  }
  if (lead == null) return true;

  final leadTarget = memberTargetForInstanceId(targets, lead.id);
  if (leadTarget == null) return false;

  final ids = workspaceTargetIds(folders);
  if (ids.isEmpty || !ids.contains(leadTarget)) return false;

  if (ids.contains(WorkspaceFolder.localTargetId)) {
    return leadTarget == WorkspaceFolder.localTargetId;
  }
  return true;
}

/// Mixed workspaces need an explicit Machines confirmation before team launch.
bool workspaceNeedsMixedPlacementInit({
  required List<WorkspaceFolder> folders,
  required String teamId,
  required Map<String, bool> initializedByTeam,
}) {
  if (workspaceTopologyOf(folders) != WorkspaceTopology.mixed) return false;
  return initializedByTeam[teamId.trim()] != true;
}

/// Writes placement totals onto [members] (`replicas`); lead always stays `1`.
List<TeamMemberConfig> applyPlacementReplicasToMembers({
  required List<TeamMemberConfig> members,
  required MemberPlacementByTarget placement,
}) {
  return [
    for (final m in members)
      if (TeamMemberNaming.isTeamLead(m))
        m.copyWith(replicas: 1)
      else
        m.copyWith(replicas: memberPlacementCountForType(placement, m.id)),
  ];
}

/// Raises stale profile [replicas] when remembered targets imply more pods.
///
/// Placement save must write `roster.overrides.replicas`. Older saves only
/// wrote `memberTargets` (`builder-0`/`builder-1`) while profile stayed at 1,
/// so createSession expanded a singleton `builder` that never matched those
/// pins and was omitted. Heal at session create / materialize so existing
/// workspaces recover without re-opening Machines.
List<TeamMemberConfig> healMemberReplicasFromTargets({
  required List<TeamMemberConfig> members,
  required MemberTargetAssignments targets,
}) {
  if (targets.isEmpty) return members;
  return [
    for (final m in members)
      if (TeamMemberNaming.isTeamLead(m))
        m.copyWith(replicas: 1)
      else
        m.copyWith(
          replicas: _max(
            m.replicas < 0 ? 0 : m.replicas,
            _pinnedInstanceCountForType(targets, m.id),
          ),
        ),
  ];
}

int _pinnedInstanceCountForType(
  MemberTargetAssignments targets,
  String typeId,
) {
  final trimmed = typeId.trim();
  if (trimmed.isEmpty) return 0;
  var count = 0;
  for (final instanceId in targets.keys) {
    final id = instanceId.trim();
    if (id == trimmed || id.startsWith('$trimmed-')) count++;
  }
  return count;
}

int _max(int a, int b) => a >= b ? a : b;

/// Infer mixed first-init from remembered targets (migration / load path).
bool inferMemberPlacementInitialized({
  required List<WorkspaceFolder> folders,
  required List<TeamMemberConfig> members,
  required MemberTargetAssignments targets,
  required bool alreadyInitialized,
}) {
  if (alreadyInitialized) return true;
  if (workspaceTopologyOf(folders) != WorkspaceTopology.mixed) return false;
  if (targets.isEmpty) return false;

  final ids = workspaceTargetIds(folders).toSet();
  for (final targetId in targets.values) {
    final trimmed = targetId.trim();
    if (trimmed.isEmpty || !ids.contains(trimmed)) return false;
  }

  final hasLead = members.any(
    (m) => m.isValid && TeamMemberNaming.isTeamLead(m),
  );
  if (hasLead &&
      !leadPlacementValid(
        folders: folders,
        members: members,
        targets: targets,
      )) {
    return false;
  }
  return true;
}

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

/// Personal launch: [primaryPath] is cwd; add-dirs are other catalog folders on
/// the same target (cross-machine paths are not reachable from one PTY).
({String workingDirectory, List<String> addDirs}) personalWorkDirsForPrimaryPath(
  List<WorkspaceFolder> catalog,
  String primaryPath,
) {
  final normalizedPrimary = normalizeWorkspacePath(primaryPath.trim());
  if (catalog.isEmpty) {
    return (
      workingDirectory: normalizedPrimary,
      addDirs: const [],
    );
  }

  final targetId =
      targetIdForFolderPaths(
        catalog,
        [normalizedPrimary],
        matchSubpaths: true,
      ) ??
      catalog.first.targetId;

  var cwd = normalizedPrimary;
  for (final folder in catalog) {
    if (folder.targetId == targetId &&
        workspacePathsEqual(folder.path, normalizedPrimary)) {
      cwd = folder.path;
      break;
    }
  }
  if (cwd.isEmpty) {
    final onTarget = folderPathsForTarget(catalog, targetId);
    cwd = onTarget.isNotEmpty ? onTarget.first : catalog.first.path;
  }

  final addDirs = <String>[
    for (final folder in catalog)
      if (folder.targetId == targetId && !workspacePathsEqual(folder.path, cwd))
        folder.path,
  ];

  return (workingDirectory: cwd, addDirs: addDirs);
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
  final roster = [
    for (final m in members)
      if (m.isValid) m,
  ];
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
  final roster = [
    for (final m in members)
      if (m.isValid) m,
  ];
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

/// Progress helper only — not a launch gate (see [workspaceNeedsMixedPlacementInit]).
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

/// Whether every expanded roster instance has a folder-backed target pin.
///
/// Pure completeness check for UI progress — not a launch gate. Launch uses
/// [workspaceNeedsMixedPlacementInit] + [leadPlacementValid] instead.
bool memberTargetsComplete({
  required List<WorkspaceFolder> workspaceFolders,
  required List<TeamMemberConfig> members,
  required MemberTargetAssignments targets,
}) {
  final roster = [
    for (final m in members)
      if (m.isValid) m,
  ];
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
