import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:uuid/uuid.dart';

import '../models/workspace.dart';
import '../models/workspace_topology.dart';
import '../models/workspace_folder.dart';
import '../models/app_session.dart';
import '../models/session_continue_overrides.dart';
import '../models/member_instance.dart';
import '../models/session_member_binding.dart';
import '../models/team_config.dart';
import '../services/storage/runtime_layout.dart';
import '../services/io/filesystem.dart';
import '../services/session/session_member_cli_locks.dart';
import '../services/session/session_team_counter.dart';
import '../services/session/team_session_member_plan.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/work_target_canonicalizer.dart';
import '../models/workspace_icon_ref.dart';
import '../services/workspace/target_liveness.dart';
import '../services/workspace/workspace_icon_service.dart';
import '../services/workspace/workspace_icon_storage.dart';
import '../services/workspace/workspace_target_remap.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/provider/workspace_trust_provisioner.dart';
import '../utils/lock_pool.dart';
import '../utils/logging/logger.dart';
import '../utils/workspace/workspace_path_utils.dart';
import '../utils/session/workspace_sessions.dart';
import 'session_repository_fs.dart';
import 'workspace_index_store.dart';

class SessionRepository {
  SessionRepository({
    String? rootDir,
    SessionLifecycleService? lifecycleService,
  }) : _rootOverride = rootDir,
       _lifecycleService = lifecycleService;

  final String? _rootOverride;
  final SessionLifecycleService? _lifecycleService;
  final _sessionFileLocks = LockPool();
  static final Map<String, List<Workspace>> _workspacesIndexByRoot = {};

  String _workspacesIndexCacheKey() {
    if (_rootOverride != null) return _rootOverride;
    if (AppStorage.isInstalled) return AppStorage.appDataRoot;
    return AppStorage.paths.basePath;
  }

  List<Workspace> _rememberWorkspacesIndex(List<Workspace> workspaces) {
    final inferred = [
      for (final workspace in workspaces)
        _withInferredMemberPlacementInit(workspace),
    ];
    final remembered = List<Workspace>.unmodifiable(inferred);
    _workspacesIndexByRoot[_workspacesIndexCacheKey()] = remembered;
    return remembered;
  }

  /// Incremental mirror of [Workspace] into the in-memory index cache and the
  /// workspaces-index.json snapshot. Mutations call this so the fast boot path
  /// (loadWorkspacesIndex) never returns a stale workspace.
  Future<void> _rememberWorkspace(Workspace workspace) async {
    final key = _workspacesIndexCacheKey();
    final current = _workspacesIndexByRoot[key];
    if (current != null) {
      _workspacesIndexByRoot[key] = List<Workspace>.unmodifiable([
        for (final existing in current)
          if (existing.workspaceId == workspace.workspaceId)
            _withInferredMemberPlacementInit(workspace)
          else
            existing,
      ]);
    }
    await WorkspaceIndexStore(await _fs()).upsert(workspace);
  }

  /// Incremental removal from the in-memory index cache and the index snapshot.
  Future<void> _forgetWorkspace(String workspaceId) async {
    final key = _workspacesIndexCacheKey();
    final current = _workspacesIndexByRoot[key];
    if (current != null) {
      _workspacesIndexByRoot[key] = List<Workspace>.unmodifiable(
        [for (final existing in current)
          if (existing.workspaceId != workspaceId) existing],
      );
    }
    await WorkspaceIndexStore(await _fs()).remove(workspaceId);
  }

  Future<T> _withSessionFile<T>(String sessionId, Future<T> Function() fn) {
    return _sessionFileLocks.synchronized(sessionId, fn);
  }

  Future<SessionRepositoryFs> _fs() async {
    // Explicit rootDir override (tests) wins; otherwise the home control plane.
    if (_rootOverride != null) {
      return SessionRepositoryFs(teampilotRoot: _rootOverride);
    }
    if (AppStorage.isInstalled) {
      final snap = AppStorage.context;
      return SessionRepositoryFs(
        teampilotRoot: snap.teampilotRoot,
        fs: snap.fs,
        layout: snap.workspace,
      );
    }
    return SessionRepositoryFs(teampilotRoot: AppStorage.paths.basePath);
  }

  /// Public accessor for the repository filesystem binding.
  Future<SessionRepositoryFs> fs() => _fs();

  Future<Workspace?> _readManifest(
    SessionRepositoryFs fs,
    String workspaceId, {
    bool indexOnly = false,
  }) async {
    final total = Stopwatch()..start();
    final raw = await fs.readText(fs.manifestFile(workspaceId));
    final readMs = total.elapsedMilliseconds;
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) {
        final workspace = Workspace.fromJson(json);
        final listSw = Stopwatch()..start();
        final sessionIds = indexOnly
            ? await fs.listSessionDirectoryIds(workspaceId)
            : await fs.listSessionIdsForWorkspace(workspaceId);
        final listMs = listSw.elapsedMilliseconds;
        if (readMs >= 50 || listMs >= 50) {
          appLogger.d(
            '[session-launch] readManifest '
            'workspace=$workspaceId indexOnly=$indexOnly '
            'readMs=$readMs listMs=$listMs sessions=${sessionIds.length}',
          );
        }
        // Migration: infer mixed placement init in-memory only when remembered
        // targets are non-empty and all host ids are still in the workspace.
        // Roster/lead is unavailable at load, so pass members: [] (lead check
        // vacuous). Disk is not rewritten here — next explicit placement save
        // persists the flag.
        return _withInferredMemberPlacementInit(
          workspace.copyWith(sessionIds: sessionIds),
        );
      }
    } on Object {
      // ignore
    }
    return null;
  }

  /// In-memory migration for mixed workspaces that already have valid pins.
  ///
  /// Skips teams with an explicit `false` entry (host-set / topology reset)
  /// so load-time infer does not undo a deliberate re-confirm requirement.
  static Workspace _withInferredMemberPlacementInit(Workspace workspace) {
    if (workspaceTopologyOf(workspace.folders) != WorkspaceTopology.mixed) {
      return workspace;
    }
    if (workspace.memberTargetsByTeam.isEmpty) return workspace;

    var nextInitialized = workspace.memberPlacementInitializedByTeam;
    var changed = false;
    for (final entry in workspace.memberTargetsByTeam.entries) {
      final teamId = entry.key.trim();
      if (teamId.isEmpty) continue;
      // Missing key → eligible for migration infer.
      // Explicit true → already initialized.
      // Explicit false → host-set reset; do not re-infer.
      if (nextInitialized.containsKey(teamId)) continue;
      final targets = rememberedMemberTargets(
        workspace.memberTargetsByTeam,
        teamId,
      );
      if (!inferMemberPlacementInitialized(
        folders: workspace.folders,
        members: const [],
        targets: targets,
        alreadyInitialized: false,
      )) {
        continue;
      }
      if (!changed) {
        nextInitialized = Map<String, bool>.from(nextInitialized);
        changed = true;
      }
      nextInitialized[teamId] = true;
    }
    if (!changed) return workspace;
    return workspace.copyWith(
      memberPlacementInitializedByTeam: nextInitialized,
    );
  }

  Future<void> _writeManifest(
    SessionRepositoryFs fs,
    Workspace workspace,
  ) async {
    await fs.ensureWorkspaceDir(workspace.workspaceId);
    final withoutSessions = workspace.copyWith(sessionIds: const []);
    await fs.writeText(
      fs.manifestFile(workspace.workspaceId),
      const JsonEncoder.withIndent('  ').convert(withoutSessions.toJson()),
    );
  }

  static bool _sameWorkspaceIds(
    List<String> diskIds,
    List<Workspace> snapshot,
  ) {
    if (diskIds.length != snapshot.length) return false;
    final diskSet = diskIds.toSet();
    return snapshot.every(
      (workspace) => diskSet.contains(workspace.workspaceId),
    );
  }

  Future<List<Workspace>> loadWorkspaces() => _loadWorkspaces(indexOnly: false);

  /// Manifest + session directory names only — no per-session JSON reads.
  ///
  /// Reads [workspaces-index.json] when present and workspace ids still match
  /// disk; otherwise rebuilds the snapshot from per-workspace manifests.
  Future<List<Workspace>> loadWorkspacesIndex() async {
    final cached = _workspacesIndexByRoot[_workspacesIndexCacheKey()];
    if (cached != null) {
      appLogger.i(
        '[boot] loadWorkspacesIndex from memory count=${cached.length}',
      );
      return cached;
    }
    final fs = await _fs();
    final store = WorkspaceIndexStore(fs);
    final readSw = Stopwatch()..start();
    final snapshot = await store.tryRead();
    final readMs = readSw.elapsedMilliseconds;
    if (snapshot != null) {
      appLogger.i(
        '[boot] loadWorkspacesIndex from snapshot count=${snapshot.length} '
        'read=${readMs}ms (validate deferred)',
      );
      unawaited(_revalidateWorkspacesIndexSnapshot(fs, store, snapshot));
      return _rememberWorkspacesIndex(snapshot);
    } else {
      appLogger.i(
        '[boot] loadWorkspacesIndex rebuilding snapshot read=${readMs}ms',
      );
    }
    final workspaces = await _loadWorkspaces(indexOnly: false);
    await store.writeAll(workspaces);
    return _rememberWorkspacesIndex(workspaces);
  }

  Future<void> _revalidateWorkspacesIndexSnapshot(
    SessionRepositoryFs fs,
    WorkspaceIndexStore store,
    List<Workspace> snapshot,
  ) async {
    final validateSw = Stopwatch()..start();
    final diskIds = await fs.listWorkspaceIds();
    final validateMs = validateSw.elapsedMilliseconds;
    if (_sameWorkspaceIds(diskIds, snapshot)) {
      appLogger.i('[boot] loadWorkspacesIndex validate ok +${validateMs}ms');
      return;
    }
    appLogger.i(
      '[boot] loadWorkspacesIndex snapshot stale '
      'disk=${diskIds.length} index=${snapshot.length} '
      'validate=${validateMs}ms',
    );
    final workspaces = await _loadWorkspaces(indexOnly: false);
    await store.writeAll(workspaces);
    _rememberWorkspacesIndex(workspaces);
  }

  Future<List<Workspace>> _loadWorkspaces({required bool indexOnly}) async {
    final fs = await _fs();
    final workspaceIds = await fs.listWorkspaceIds();
    final workspaces = await Future.wait(
      workspaceIds.map(
        (workspaceId) => _readManifest(fs, workspaceId, indexOnly: indexOnly),
      ),
    );
    return [
      for (final workspace in workspaces)
        if (workspace != null) workspace,
    ];
  }

  Future<List<AppSession>> loadSessions() async {
    final fs = await _fs();
    final workspaceIds = await fs.listWorkspaceIds();
    final mapsPerWorkspace = await Future.wait(
      workspaceIds.map(fs.listSessionJsonMapsForWorkspace),
    );
    final sessions = <AppSession>[];
    for (final maps in mapsPerWorkspace) {
      for (final json in maps) {
        try {
          sessions.add(AppSession.fromJson(json));
        } on Object {
          continue;
        }
      }
    }
    sessions.sort((a, b) {
      final au = a.updatedAt != 0 ? a.updatedAt : a.createdAt;
      final bu = b.updatedAt != 0 ? b.updatedAt : b.createdAt;
      return bu.compareTo(au);
    });
    return sessions;
  }

  Future<List<AppSession>> loadSessionsForWorkspace(String workspaceId) async {
    final fs = await _fs();
    final sessions = <AppSession>[];
    for (final json in await fs.listSessionJsonMapsForWorkspace(workspaceId)) {
      try {
        sessions.add(AppSession.fromJson(json));
      } on Object {
        continue;
      }
    }
    sessions.sort((a, b) {
      final au = a.updatedAt != 0 ? a.updatedAt : a.createdAt;
      final bu = b.updatedAt != 0 ? b.updatedAt : b.createdAt;
      return bu.compareTo(au);
    });
    return sessions;
  }

  /// Creates a new, independent workspace for [folders].
  ///
  /// Always writes a fresh manifest (no path-based reuse/merge — dedup and
  /// folder merging are owned by the workspace catalog at a higher layer).
  Future<Workspace> createWorkspace(
    List<WorkspaceFolder> folders, {
    String display = '',
  }) async {
    final fs = await _fs();
    final normalized = [
      for (final f in folders)
        if (f.path.trim().isNotEmpty)
          f.copyWith(path: normalizeWorkspacePath(f.path)),
    ];
    if (normalized.isEmpty) {
      throw ArgumentError('createWorkspace requires at least one folder path');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final workspace = Workspace(
      workspaceId: const Uuid().v4(),
      folders: normalized,
      display: display.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await _writeManifest(fs, workspace);
    await _rememberWorkspace(workspace);
    return workspace;
  }

  Future<Workspace?> updateWorkspaceMetadata(
    String workspaceId, {
    String? display,
    String? defaultProfileId,
    bool? rootSandboxEnvOptIn,
  }) async {
    final fs = await _fs();
    final existing = await _readManifest(fs, workspaceId);
    if (existing == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = existing.copyWith(
      display: display != null ? display.trim() : existing.display,
      defaultProfileId: defaultProfileId != null
          ? defaultProfileId.trim()
          : existing.defaultProfileId,
      folders: existing.folders,
      rootSandboxEnvOptIn: rootSandboxEnvOptIn ?? existing.rootSandboxEnvOptIn,
      updatedAt: now,
    );
    await _writeManifest(fs, updated);
    await _rememberWorkspace(updated);
    return updated;
  }

  Future<Workspace?> applyWorkspaceIcon(
    String workspaceId,
    WorkspaceIconRef icon,
  ) async {
    final fs = await _fs();
    final existing = await _readManifest(fs, workspaceId);
    if (existing == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final workspaceDir = fs.workspaceDir(workspaceId);
    final iconService = WorkspaceIconService(
      storage: WorkspaceIconStorage(filesystem: fs.fs),
    );
    await iconService.deleteCustomFilesForTransition(
      workspaceDir: workspaceDir,
      workspaceId: workspaceId,
      previous: existing.icon,
      next: icon,
    );
    final updated = existing.copyWith(icon: icon, updatedAt: now);
    await _writeManifest(fs, updated);
    await _rememberWorkspace(updated);
    return updated;
  }

  Future<Workspace?> importCustomWorkspaceIcon(
    String workspaceId,
    String localSourcePath,
  ) async {
    final fs = await _fs();
    final existing = await _readManifest(fs, workspaceId);
    if (existing == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final workspaceDir = fs.workspaceDir(workspaceId);
    final iconService = WorkspaceIconService(
      storage: WorkspaceIconStorage(filesystem: fs.fs),
    );
    final customIcon = await iconService.importCustomFromLocalFile(
      workspaceDir: workspaceDir,
      workspaceId: workspaceId,
      localSourcePath: localSourcePath,
    );
    await iconService.deleteCustomFilesForTransition(
      workspaceDir: workspaceDir,
      workspaceId: workspaceId,
      previous: existing.icon,
      next: customIcon,
    );
    final updated = existing.copyWith(icon: customIcon, updatedAt: now);
    await _writeManifest(fs, updated);
    await _rememberWorkspace(updated);
    return updated;
  }

  /// Replace a workspace's folders wholesale (path + per-folder targetId).
  /// Used by the workspace target picker to move a workspace onto another
  /// machine (sets [WorkspaceFolder.targetId] on all folders).
  Future<Workspace?> updateWorkspaceFolders(
    String workspaceId,
    List<WorkspaceFolder> folders,
  ) async {
    final fs = await _fs();
    final existing = await _readManifest(fs, workspaceId);
    if (existing == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final nextFolders = [
      for (final f in folders)
        if (f.path.trim().isNotEmpty)
          f.copyWith(path: normalizeWorkspacePath(f.path)),
    ];
    final previousTopology = workspaceTopologyOf(existing.folders);
    final previousTargetIds = workspaceTargetIds(existing.folders);
    final nextTopology = workspaceTopologyOf(nextFolders);
    final nextTargetIds = workspaceTargetIds(nextFolders);
    final becameMixed =
        previousTopology != WorkspaceTopology.mixed &&
        nextTopology == WorkspaceTopology.mixed;
    final targetSetChanged = !_sameTargetIdSet(
      previousTargetIds,
      nextTargetIds,
    );
    final foldersChanged = !listEquals(nextFolders, existing.folders);
    final mixedInvolved =
        previousTopology == WorkspaceTopology.mixed ||
        nextTopology == WorkspaceTopology.mixed;
    final nextInitialized =
        (becameMixed || targetSetChanged || (foldersChanged && mixedInvolved))
        ? <String, bool>{
            for (final teamId in existing.memberTargetsByTeam.keys)
              if (teamId.trim().isNotEmpty) teamId.trim(): false,
          }
        : existing.memberPlacementInitializedByTeam;
    final updated = existing.copyWith(
      folders: nextFolders,
      memberPlacementInitializedByTeam: nextInitialized,
      updatedAt: now,
    );
    await _writeManifest(fs, updated);
    await _rememberWorkspace(updated);
    return updated;
  }

  static bool _sameTargetIdSet(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    return Set<String>.from(a).containsAll(b);
  }

  /// Persists remembered mixed-workspace machine pins for a team.
  Future<Workspace?> updateWorkspaceMemberTargets(
    String workspaceId,
    String teamId, {
    required MemberTargetAssignments targets,
  }) async {
    return _updateWorkspaceMemberTargetsAndInit(
      workspaceId,
      teamId,
      targets: targets,
      markInitialized: false,
    );
  }

  /// Persists member targets and marks placement initialized for [teamId].
  ///
  /// Returns the updated [Workspace] manifest (or `null` when the workspace
  /// does not exist) so callers can patch in-memory snapshots without a full
  /// disk rescan.
  Future<Workspace?> updateWorkspaceMemberPlacement(
    String workspaceId,
    String teamId, {
    required MemberTargetAssignments targets,
  }) async {
    return _updateWorkspaceMemberTargetsAndInit(
      workspaceId,
      teamId,
      targets: targets,
      markInitialized: true,
    );
  }

  Future<Workspace?> _updateWorkspaceMemberTargetsAndInit(
    String workspaceId,
    String teamId, {
    required MemberTargetAssignments targets,
    required bool markInitialized,
  }) async {
    final trimmedTeam = teamId.trim();
    if (trimmedTeam.isEmpty) return null;
    final fs = await _fs();
    final existing = await _readManifest(fs, workspaceId);
    if (existing == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final nextByTeam = Map<String, MemberTargetAssignments>.from(
      existing.memberTargetsByTeam,
    );
    final normalized = <String, String>{};
    for (final entry in targets.entries) {
      final memberId = entry.key.trim();
      final targetId = entry.value.trim();
      if (memberId.isEmpty || targetId.isEmpty) continue;
      normalized[memberId] = targetId;
    }
    if (normalized.isEmpty) {
      nextByTeam.remove(trimmedTeam);
    } else {
      nextByTeam[trimmedTeam] = normalized;
    }
    var nextInitialized = existing.memberPlacementInitializedByTeam;
    if (markInitialized) {
      nextInitialized = Map<String, bool>.from(nextInitialized)
        ..[trimmedTeam] = true;
    }
    final updated = existing.copyWith(
      memberTargetsByTeam: nextByTeam,
      memberPlacementInitializedByTeam: nextInitialized,
      updatedAt: now,
    );
    await _writeManifest(fs, updated);
    await _rememberWorkspace(updated);
    return updated;
  }

  Future<({Workspace workspace, List<AppSession> sessions})>
  remapWorkspaceTarget(
    String workspaceId, {
    required String fromTargetId,
    required String toTargetId,
    required TargetLiveness liveness,
  }) async {
    final from = fromTargetId.trim();
    final to = toTargetId.trim();
    if (from.isEmpty || to.isEmpty) {
      throw ArgumentError('fromTargetId and toTargetId must be non-empty');
    }
    final fs = await _fs();
    final existing = await _readManifest(fs, workspaceId);
    if (existing == null) {
      throw StateError('Workspace "$workspaceId" not found');
    }
    final sessions = await loadSessionsForWorkspace(workspaceId);
    if (!WorkspaceTargetRemap.usesTarget(
      folders: existing.folders,
      memberTargetsByTeam: existing.memberTargetsByTeam,
      sessions: sessions,
      targetId: from,
    )) {
      throw StateError('Nothing to remap for target "$from"');
    }
    if (from != to && !await liveness.isAlive(to)) {
      throw StateError('Destination target "$to" is not available');
    }

    final applied = WorkspaceTargetRemap.apply(
      folders: existing.folders,
      memberTargetsByTeam: existing.memberTargetsByTeam,
      sessions: sessions,
      fromTargetId: from,
      toTargetId: to,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = existing.copyWith(
      folders: applied.folders,
      memberTargetsByTeam: applied.memberTargetsByTeam,
      updatedAt: now,
    );
    await _writeManifest(fs, updated);

    final writtenSessions = <AppSession>[];
    for (final session in applied.sessions) {
      final written = session.copyWith(updatedAt: now);
      writtenSessions.add(written);
      try {
        await _writeSession(fs, written);
      } on Object catch (error, stackTrace) {
        appLogger.e(
          '[workspace] remap session write failed '
          'workspace=$workspaceId session=${session.sessionId}',
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }
    }
    return (workspace: updated, sessions: writtenSessions);
  }

  /// Provisions trust metadata (git-root trusted projects) for [workspace].
  ///
  /// No longer called from mutation paths; background provisioning and the
  /// launch trust gate are owned by the workspace catalog.
  Future<void> provisionWorkspaceTrust(Workspace workspace) async {
    final fs = await _fs();
    final layout = RuntimeLayout(teampilotRoot: fs.teampilotRoot, fs: fs.fs);
    await WorkspaceTrustProvisioner(
      layout: layout,
      fs: fs.fs,
    ).provisionWorkspace(
      workspaceId: workspace.workspaceId,
      directories: workspace.folderPaths,
    );
  }

  Future<({Filesystem fs, RuntimeLayout layout})> _counterContext() async {
    if (_rootOverride == null && AppStorage.isInstalled) {
      final snap = AppStorage.context;
      return (fs: snap.fs, layout: snap.layout);
    }
    final teampilotRoot = _rootOverride ?? AppStorage.paths.basePath;
    final fs = AppStorage.fs;
    return (
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: teampilotRoot, fs: fs),
    );
  }

  /// Creates a session record, returning it together with the workspace as
  /// persisted by the call (member pins are written when the team plan
  /// requires it, so callers can patch in-memory snapshots without a rescan).
  Future<({AppSession session, Workspace workspace})> createSession(
    String workspaceId, {
    String sessionTeam = '',
    List<TeamMemberConfig> rosterMembers = const [],
    Map<String, CliTool> memberClis = const {},
    CliTool? cli,
    String? provider,
    String? model,
    String? effort,
    String? presetId,
    String? workingDirectory,
    String? fixedSessionId,
    String? expertKey,
    SessionContinueOverrides? continueOverrides,
    List<SessionMemberBinding>? members,
    Map<String, String>? memberTargets,
    Workspace? knownWorkspace,
  }) async {
    final total = Stopwatch()..start();
    var stepAt = total.elapsedMilliseconds;
    void mark(String name) {
      final now = total.elapsedMilliseconds;
      appLogger.d(
        '[session-launch] createSession.$name '
        'workspace=$workspaceId ms=${now - stepAt} totalMs=$now',
      );
      stepAt = now;
    }

    final fs = await _fs();
    mark('bind-fs');
    // Launch already has the workspace snapshot; skip re-reading every
    // session.json (listSessionIdsForWorkspace) — create only needs folders /
    // placement fields, and directory listing happens lazily on manifest read.
    Workspace? workspace = knownWorkspace != null &&
            knownWorkspace.workspaceId == workspaceId
        ? knownWorkspace
        : null;
    if (workspace != null) {
      mark('reuse-workspace');
    } else {
      workspace = await _readManifest(fs, workspaceId, indexOnly: true);
      mark('read-manifest');
    }
    if (workspace == null) {
      throw StateError('Unknown workspaceId: $workspaceId');
    }
    final trimmedTeam = sessionTeam.trim();
    var cliTeamName = '';
    var resolvedMembers = const <SessionMemberBinding>[];
    var sessionTargets = const <String, String>{};

    if (trimmedTeam.isNotEmpty) {
      final plan = buildTeamSessionMemberPlan(
        workspace: workspace,
        teamId: trimmedTeam,
        rosterMembers: rosterMembers,
        memberClis: memberClis,
      );

      if (members != null) {
        final stagedIds = {
          for (final m in members) m.rosterMemberId,
        };
        final planIds = {
          for (final m in plan.members) m.rosterMemberId,
        };
        if (stagedIds.length != members.length ||
            !setEquals(stagedIds, planIds)) {
          throw StateError(
            'staged members disagree with placement: '
            'staged=$stagedIds plan=$planIds',
          );
        }
        resolvedMembers = List<SessionMemberBinding>.unmodifiable(members);
        // Prefer staged targets only when keys match plan inclusion; otherwise
        // fall back to plan (unlike member id mismatch, which is a hard error).
        if (memberTargets != null &&
            setEquals(memberTargets.keys.toSet(), planIds)) {
          sessionTargets = Map<String, String>.unmodifiable(memberTargets);
        } else {
          sessionTargets = plan.memberTargets;
        }
      } else {
        resolvedMembers = plan.members;
        sessionTargets = plan.memberTargets;
      }

      if (plan.persistTargets) {
        await updateWorkspaceMemberTargets(
          workspaceId,
          trimmedTeam,
          targets: plan.memberTargets,
        );
        workspace =
            await _readManifest(fs, workspaceId) ??
            workspace.copyWith(
              memberTargetsByTeam: {
                ...workspace.memberTargetsByTeam,
                trimmedTeam: plan.memberTargets,
              },
            );
      }

      final counterCtx = await _counterContext();
      final counter = SessionTeamCounter(
        fs: counterCtx.fs,
        layout: counterCtx.layout,
      );
      cliTeamName = await counter.nextCliTeamName(trimmedTeam);
      mark('team-plan');
    }

    final pinnedId = fixedSessionId?.trim() ?? '';
    final sessionId = pinnedId.isNotEmpty ? pinnedId : const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final resolvedExpertKey = expertKey?.trim() ?? '';
    final session = AppSession(
      sessionId: sessionId,
      workspaceId: workspaceId,
      folders: Workspace.foldersForPrimaryPath(
        workspace.folders,
        workingDirectory ?? '',
        defaultTargetId: _lifecycleService == null
            ? null
            : WorkTargetCanonicalizer.defaultFolderTargetId(
                _lifecycleService!.currentHome,
              ),
      ),
      display: '',
      sessionTeam: sessionTeam,
      profileId: '',
      cliTeamName: cliTeamName,
      cli: trimmedTeam.isEmpty ? cli : null,
      provider: trimmedTeam.isEmpty ? (provider?.trim() ?? '') : '',
      model: trimmedTeam.isEmpty ? (model?.trim() ?? '') : '',
      effort: trimmedTeam.isEmpty ? (effort?.trim() ?? '') : '',
      presetId: trimmedTeam.isEmpty ? (presetId?.trim() ?? '') : '',
      members: resolvedMembers,
      memberTargets: sessionTargets,
      launchState: AppSessionLaunchState.created,
      createdAt: now,
      updatedAt: now,
      expertKey: resolvedExpertKey,
      continueOverrides: continueOverrides ?? const SessionContinueOverrides(),
    );
    await fs.ensureSessionDir(workspaceId, sessionId);
    mark('ensure-dir');
    await fs.writeText(
      fs.sessionFile(workspaceId, sessionId),
      jsonEncode(session.toJson()),
    );
    mark('write-session');
    appLogger.d(
      '[session-launch] createSession done '
      'session=$sessionId ms=${total.elapsedMilliseconds}',
    );
    // The manifest read above predates the session write, so stamp the new
    // sessionId (newest first, createdAt desc) for the index mirror. The
    // returned workspace keeps its pre-session sessionIds — callers append
    // the new id themselves.
    await _rememberWorkspace(
      workspace.sessionIds.contains(sessionId)
          ? workspace
          : workspace.copyWith(
              sessionIds: [sessionId, ...workspace.sessionIds],
            ),
    );
    return (session: session, workspace: workspace);
  }

  Future<AppSession?> _readSession(
    SessionRepositoryFs fs,
    String workspaceId,
    String sessionId,
  ) async {
    final raw = await fs.readText(fs.sessionFile(workspaceId, sessionId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) {
        return AppSession.fromJson(json);
      }
    } on Object {
      return null;
    }
    return null;
  }

  Future<AppSession?> _findSession(
    SessionRepositoryFs fs,
    String sessionId,
  ) async {
    for (final workspaceId in await fs.listWorkspaceIds()) {
      final session = await _readSession(fs, workspaceId, sessionId);
      if (session != null) return session;
    }
    return null;
  }

  Future<void> _writeSession(SessionRepositoryFs fs, AppSession session) async {
    final workspaceId = session.workspaceId.trim();
    if (workspaceId.isEmpty) {
      throw StateError('Session ${session.sessionId} missing workspaceId');
    }
    await fs.writeText(
      fs.sessionFile(workspaceId, session.sessionId),
      jsonEncode(session.toJson()),
    );
  }

  Future<void> markSessionLaunched(String sessionId) {
    return markSessionStarted(sessionId);
  }

  Future<SessionMemberBinding> ensureMemberBinding(
    String sessionId,
    String rosterMemberId, {
    required CliTool cli,
    String? typeId,
  }) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) {
        throw StateError('Unknown sessionId: $sessionId');
      }
      final trimmedMemberId = rosterMemberId.trim();
      if (trimmedMemberId.isEmpty) {
        throw ArgumentError.value(
          rosterMemberId,
          'rosterMemberId',
          'must not be empty',
        );
      }
      final found = existing.bindingFor(trimmedMemberId);
      if (found != null) return found;

      final now = DateTime.now().millisecondsSinceEpoch;
      final binding = SessionMemberBinding(
        rosterMemberId: trimmedMemberId,
        typeId: (typeId ?? trimmedMemberId).trim(),
        taskId: const Uuid().v4(),
        cli: cli,
      );
      await _writeSession(
        fs,
        existing.copyWith(
          members: [...existing.members, binding],
          updatedAt: now,
        ),
      );
      return binding;
    });
  }

  /// Records a CLI-native resume id for [sessionId]. Team sessions store it on
  /// the matching member binding ([rosterMemberId]); personal sessions store it
  /// at the session level. No-op when already equal. See
  /// `docs/session-resume-architecture.md`.
  Future<void> recordNativeSessionId(
    String sessionId, {
    required String tool,
    required String nativeId,
    String? rosterMemberId,
  }) {
    final trimmedTool = tool.trim();
    final trimmedId = nativeId.trim();
    if (trimmedTool.isEmpty || trimmedId.isEmpty) return Future.value();
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      final memberId = rosterMemberId?.trim() ?? '';
      AppSession updated;
      if (memberId.isNotEmpty) {
        final binding = existing.bindingFor(memberId);
        if (binding == null) return;
        final next = binding.withNativeSessionId(trimmedTool, trimmedId);
        if (identical(next, binding)) return;
        updated = existing.copyWith(
          members: [
            for (final m in existing.members)
              if (m.rosterMemberId == memberId) next else m,
          ],
        );
      } else {
        final next = existing.withNativeSessionId(trimmedTool, trimmedId);
        if (identical(next, existing)) return;
        updated = next;
      }
      await _writeSession(
        fs,
        updated.copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch),
      );
    });
  }

  Future<void> markSessionStarted(String sessionId) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      if (existing.launchState == AppSessionLaunchState.started) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(
        fs,
        existing.copyWith(
          launchState: AppSessionLaunchState.started,
          updatedAt: now,
        ),
      );
    });
  }

  Future<void> renameSession(String sessionId, String newName) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(
        fs,
        existing.copyWith(display: newName, updatedAt: now),
      );
    });
  }

  Future<void> touchSession(String sessionId) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(fs, existing.copyWith(updatedAt: now));
    });
  }

  Future<void> toggleSessionPin(String sessionId) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(
        fs,
        existing.copyWith(pinned: !existing.pinned, updatedAt: now),
      );
    });
  }

  Future<void> updateSessionTeam(String sessionId, String sessionTeam) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(
        fs,
        existing.copyWith(sessionTeam: sessionTeam, updatedAt: now),
      );
    });
  }

  Future<void> updateContinueOverrides(
    String sessionId,
    SessionContinueOverrides overrides,
  ) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(
        fs,
        existing.copyWith(continueOverrides: overrides, updatedAt: now),
      );
    });
  }

  /// Patches Simple-launch identity fields without touching [AppSession.continueOverrides].
  Future<void> updateSimpleLaunchIdentity(
    String sessionId, {
    String? presetId,
    String? provider,
    String? model,
    String? effort,
  }) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(
        fs,
        existing.copyWith(
          presetId: presetId != null ? presetId.trim() : existing.presetId,
          provider: provider != null ? provider.trim() : existing.provider,
          model: model != null ? model.trim() : existing.model,
          effort: effort != null ? effort.trim() : existing.effort,
          updatedAt: now,
        ),
      );
    });
  }

  /// Persists a manual arrangement: stamps each session's [AppSession.sortOrder]
  /// to its position in [orderedSessionIds] (1-based, so untouched sessions at
  /// the default `0` keep sorting first). Sessions absent from disk are skipped.
  Future<void> reorderSessions(List<String> orderedSessionIds) async {
    for (var i = 0; i < orderedSessionIds.length; i++) {
      final sessionId = orderedSessionIds[i];
      final order = i + 1;
      await _withSessionFile(sessionId, () async {
        final fs = await _fs();
        final existing = await _findSession(fs, sessionId);
        if (existing == null || existing.sortOrder == order) return;
        await _writeSession(fs, existing.copyWith(sortOrder: order));
      });
    }
  }

  Future<void> clearAllSessionTeams() async {
    final fs = await _fs();
    for (final json in await fs.listAllSessionJsonMaps()) {
      try {
        final session = AppSession.fromJson(json);
        await _withSessionFile(session.sessionId, () async {
          final innerFs = await _fs();
          final fresh = await _findSession(innerFs, session.sessionId);
          if (fresh == null) return;
          await _writeSession(
            innerFs,
            fresh.copyWith(
              sessionTeam: '',
              cliTeamName: '',
              members: const [],
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        });
      } on Object {
        continue;
      }
    }
  }

  Future<void> deleteSession(String sessionId) async {
    await _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      final workspaceId = existing.workspaceId.trim();
      final teamId = existing.sessionTeam.trim();
      if (teamId.isNotEmpty) {
        await _lifecycleService?.destroyCliState(
          workspaceId: workspaceId,
          teamId: teamId,
          sessionId: sessionId,
          session: existing,
        );
      } else if (workspaceId.isNotEmpty) {
        await _lifecycleService?.destroyStandaloneCliState(
          workspaceId: workspaceId,
          sessionId: sessionId,
          session: existing,
        );
      }
      await fs.deleteSessionDir(workspaceId, sessionId);
      final workspace = await _readManifest(fs, workspaceId);
      if (workspace != null) {
        await _writeManifest(
          fs,
          workspace.copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch),
        );
        // Mirror the sessionIds change into the index snapshot.
        final cachedList = _workspacesIndexByRoot[_workspacesIndexCacheKey()];
        Workspace? cached;
        for (final w in cachedList ?? const <Workspace>[]) {
          if (w.workspaceId == workspaceId) {
            cached = w;
            break;
          }
        }
        if (cached != null) {
          await _rememberWorkspace(
            cached.copyWith(
              sessionIds: [
                for (final id in cached.sessionIds)
                  if (id != sessionId) id,
              ],
            ),
          );
        }
      }
    });
  }

  Future<({Workspace workspace, List<AppSession> sessions})> cloneWorkspace(
    String sourceWorkspaceId, {
    String? display,
    List<TeamMemberConfig> rosterMembers = const [],
  }) async {
    final fs = await _fs();
    final source = await _readManifest(fs, sourceWorkspaceId);
    if (source == null) {
      throw StateError('Unknown workspaceId: $sourceWorkspaceId');
    }

    final sourceSessions = sessionsForWorkspace(source, await loadSessions());
    final now = DateTime.now().millisecondsSinceEpoch;
    final newWorkspaceId = const Uuid().v4();
    final newWorkspace = Workspace(
      workspaceId: newWorkspaceId,
      folders: List.of(source.folders),
      display: (display ?? source.display).trim(),
      icon: source.icon,
      createdAt: now,
      updatedAt: now,
    );
    await _writeManifest(fs, newWorkspace);

    final clonedSessions = <AppSession>[];
    for (final old in sourceSessions) {
      clonedSessions.add(
        await _cloneSessionRecord(
          fs,
          old,
          newWorkspaceId,
          rosterMembers: rosterMembers,
        ),
      );
    }

    await _rememberWorkspace(
      newWorkspace.copyWith(
        sessionIds: [for (final s in clonedSessions) s.sessionId],
      ),
    );
    return (
      workspace: (await _readManifest(fs, newWorkspaceId)) ?? newWorkspace,
      sessions: clonedSessions,
    );
  }

  Future<AppSession> _cloneSessionRecord(
    SessionRepositoryFs fs,
    AppSession source,
    String targetWorkspaceId, {
    required List<TeamMemberConfig> rosterMembers,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var cliTeamName = '';
    var members = const <SessionMemberBinding>[];
    final trimmedTeam = source.sessionTeam.trim();
    if (trimmedTeam.isNotEmpty) {
      final valid = rosterMembers.where((m) => m.isValid).toList();
      if (valid.isNotEmpty) {
        final counterCtx = await _counterContext();
        final counter = SessionTeamCounter(
          fs: counterCtx.fs,
          layout: counterCtx.layout,
        );
        cliTeamName = await counter.nextCliTeamName(trimmedTeam);
        members = [
          for (final inst in expandTeamRoster(valid))
            SessionMemberBinding(
              rosterMemberId: inst.instanceId,
              typeId: inst.type.id,
              taskId: const Uuid().v4(),
              cli: copyCliFromSourceBinding(
                sourceMembers: source.members,
                rosterMemberId: inst.instanceId,
                typeId: inst.type.id,
              ),
            ),
        ];
      }
    }

    final sessionId = const Uuid().v4();
    final session = AppSession(
      sessionId: sessionId,
      workspaceId: targetWorkspaceId,
      folders: List.of(source.folders),
      display: source.display,
      sessionTeam: source.sessionTeam,
      cliTeamName: cliTeamName,
      members: members,
      launchState: AppSessionLaunchState.created,
      createdAt: now,
      updatedAt: now,
    );
    await fs.ensureSessionDir(targetWorkspaceId, sessionId);
    await _writeSession(fs, session);
    return session;
  }

  Future<void> deleteWorkspace(String workspaceId) async {
    final fs = await _fs();
    final workspace = await _readManifest(fs, workspaceId);
    if (workspace == null) return;

    final sessions = sessionsForWorkspace(workspace, await loadSessions());
    for (final session in sessions) {
      await deleteSession(session.sessionId);
    }

    await WorkspaceIconService(
      storage: WorkspaceIconStorage(filesystem: fs.fs),
    ).deleteAllCustomFilesForWorkspace(
      workspaceDir: fs.workspaceDir(workspaceId),
      workspaceId: workspaceId,
      icon: workspace.icon,
    );

    await fs.deleteWorkspaceDir(workspaceId);
    await _forgetWorkspace(workspaceId);
  }
}
