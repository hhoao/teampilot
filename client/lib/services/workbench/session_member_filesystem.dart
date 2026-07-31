import '../../models/workspace_launch_context.dart';
import '../../models/workspace_topology.dart';
import '../io/filesystem.dart';
import '../session/session_lifecycle_service.dart';
import '../workspace/workspace_tools_scope.dart';

/// Resolves the work-plane [Filesystem] for a session seat.
///
/// Prefer an already-resolved [WorkspaceToolsScopeState] slice that matches the
/// member's launch target (avoids a redundant SSH reconnect). Fall back to
/// [SessionLifecycleService.launchWorkContext] — the same path History uses.
///
/// Do **not** use [WorkspaceToolsScopeState.tools] alone: that plane follows
/// workspace cwd and is often still local while a roster member runs on SSH.
Future<Filesystem> resolveSessionMemberFilesystem({
  required SessionLifecycleService lifecycle,
  required WorkspaceLaunchContext launchContext,
  String? memberId,
  WorkspaceToolsScopeState? toolsScope,
}) async {
  final mid = memberId?.trim();
  final effectiveMemberId = (mid == null || mid.isEmpty) ? null : mid;
  final targetId = lifecycle
      .launchWorkTarget(launchContext, memberId: effectiveMemberId)
      .id;

  if (toolsScope != null) {
    for (final slice in toolsScope.targetSlices) {
      if (slice.targetId == targetId) {
        return slice.tools.context.filesystem;
      }
    }
    final active = toolsScope.tools;
    if (active != null && active.targetId == targetId) {
      return active.context.filesystem;
    }
  }

  final roots = await lifecycle.launchWorkContext(
    launchContext,
    memberId: effectiveMemberId,
  );
  return roots.filesystem;
}

/// Folder roots on the member's launch target (not the full mixed catalog).
List<String> sessionMemberFolderPaths({
  required SessionLifecycleService lifecycle,
  required WorkspaceLaunchContext launchContext,
  String? memberId,
}) {
  final mid = memberId?.trim();
  final effectiveMemberId = (mid == null || mid.isEmpty) ? null : mid;
  final targetId = lifecycle
      .launchWorkTarget(launchContext, memberId: effectiveMemberId)
      .id;
  return folderPathsForTarget(launchContext.folderCatalog, targetId);
}
