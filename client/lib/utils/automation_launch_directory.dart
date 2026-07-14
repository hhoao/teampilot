import '../models/automation.dart';
import '../models/workspace.dart';
import 'workspace_path_utils.dart';

/// Session cwd for launch-prompt automation dispatch — mirrors landing submit.
String? automationLaunchWorkingDirectory(
  Automation automation, {
  Workspace? workspace,
}) {
  final worktree = automation.workingDirectoryPath?.trim();
  if (worktree != null && worktree.isNotEmpty) {
    return normalizeWorkspacePath(worktree);
  }
  final project = automation.projectFolderPath?.trim();
  if (project != null && project.isNotEmpty) {
    return normalizeWorkspacePath(project);
  }
  final fallback = workspace?.firstFolderPath.trim() ?? '';
  if (fallback.isEmpty) return null;
  return normalizeWorkspacePath(fallback);
}
