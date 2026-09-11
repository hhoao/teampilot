import 'package:flutter/foundation.dart';

import 'app_session.dart';
import 'workspace.dart';
import 'workspace_folder.dart';
import 'workspace_topology.dart';

/// Session launch scoped to its workspace folder catalog.
@immutable
class WorkspaceLaunchContext {
  const WorkspaceLaunchContext({
    required this.session,
    required this.workspace,
    required this.usesPosixPaths,
  });

  final AppSession session;
  final Workspace workspace;

  /// Path style of the active home storage plane (WSL/SSH use POSIX paths).
  final bool usesPosixPaths;

  /// Authoritative folder catalog: workspace manifest wins on path collisions;
  /// session-only paths (e.g. worktree override) are appended.
  List<WorkspaceFolder> get folderCatalog => mergeWorkspaceFolderCatalog(
    sessionFolders: session.folders,
    workspaceFolders: workspace.folders,
    usesPosixPaths: usesPosixPaths,
  );
}
