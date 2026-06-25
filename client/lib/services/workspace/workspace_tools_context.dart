import '../../models/workspace_folder.dart';
import '../../models/workspace_topology.dart';
import '../session/session_lifecycle_service.dart';
import '../storage/runtime_context.dart';

/// Resolved storage backend for the workspace file tree / source-control panels.
class WorkspaceToolsContext {
  const WorkspaceToolsContext({
    required this.targetId,
    required this.context,
  });

  final String targetId;
  final RuntimeContext context;

  /// Picks the machine for [paths] against [folders] and materializes its
  /// work-plane [RuntimeContext].
  static Future<WorkspaceToolsContext> resolve({
    required SessionLifecycleService lifecycle,
    required List<WorkspaceFolder> folders,
    required List<String> paths,
  }) async {
    final probePaths = [
      for (final raw in paths)
        if (raw.trim().isNotEmpty) raw.trim(),
    ];
    final targetId =
        targetIdForFolderPaths(
          folders,
          probePaths,
          matchSubpaths: true,
        ) ??
        (folders.isNotEmpty
            ? folders.first.targetId
            : WorkspaceFolder.localTargetId);
    final context = await lifecycle.resolveWorkContextForTargetId(targetId);
    return WorkspaceToolsContext(targetId: targetId, context: context);
  }

  /// Workspace folder paths on [targetId]; drops roots pinned to another machine.
  static List<String> rootsOnTarget({
    required List<WorkspaceFolder> folders,
    required String targetId,
    required String primaryPath,
    required List<String> additionalPaths,
    required RuntimeContext context,
  }) =>
      rootsForTarget(
        folders: folders,
        targetId: targetId,
        primaryPath: primaryPath,
        additionalPaths: additionalPaths,
        context: context,
        includeCatalogPaths: false,
      );

  /// All folder roots on [targetId] for multi-target file trees.
  static List<String> rootsForTarget({
    required List<WorkspaceFolder> folders,
    required String targetId,
    required String primaryPath,
    required List<String> additionalPaths,
    required RuntimeContext context,
    bool includeCatalogPaths = true,
  }) {
    final pathCtx = context.filesystem.pathContext;
    final roots = <String>[];
    if (includeCatalogPaths) {
      for (final raw in folderPathsForTarget(folders, targetId)) {
        if (raw.isEmpty) continue;
        final normalized = pathCtx.normalize(raw);
        if (!roots.contains(normalized)) roots.add(normalized);
      }
    }
    for (final raw in [primaryPath, ...additionalPaths]) {
      if (raw.isEmpty) continue;
      final onTarget = targetIdForFolderPaths(
        folders,
        [raw],
        matchSubpaths: true,
      );
      if (onTarget != null && onTarget != targetId) continue;
      final normalized = pathCtx.normalize(raw);
      if (!roots.contains(normalized)) roots.add(normalized);
    }
    return roots;
  }
}
