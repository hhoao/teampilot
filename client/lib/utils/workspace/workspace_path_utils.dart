import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/workspace_folder.dart';
import '../../services/storage/app_storage.dart';
import '../../services/session/launch_command_builder.dart';

/// Normalizes a filesystem path for stable comparison and storage.
///
/// Remote/SSH paths starting with `~` are kept as trimmed text only.
/// On Windows + WSL storage, Windows picker paths are converted to `/mnt/...`.
String normalizeWorkspacePath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty || trimmed.startsWith('~')) return trimmed;
  final String normalized;
  if (trimmed.startsWith('/') && !trimmed.startsWith('//')) {
    normalized = p.Context(style: p.Style.posix).normalize(trimmed);
  } else {
    normalized = p.normalize(trimmed);
  }
  if (Platform.isWindows &&
      AppStorage.isInstalled &&
      AppStorage.usesPosixPaths) {
    final wsl = LaunchCommandBuilder.windowsPathToWsl(normalized);
    if (wsl != null) {
      return p.Context(style: p.Style.posix).normalize(wsl);
    }
  }
  return normalized;
}

bool workspacePathsEqual(String a, String b) {
  return normalizeWorkspacePath(a) == normalizeWorkspacePath(b);
}

bool workspacePathsContains(Iterable<String> paths, String target) {
  final normalized = normalizeWorkspacePath(target);
  for (final existing in paths) {
    if (normalizeWorkspacePath(existing) == normalized) return true;
  }
  return false;
}

/// Whether [path] is exactly [folderPath] or a subpath of it.
bool workspacePathUnderFolder(String path, String folderPath) {
  final normalized = normalizeWorkspacePath(path.trim());
  final root = normalizeWorkspacePath(folderPath.trim());
  if (normalized.isEmpty || root.isEmpty) return false;
  if (workspacePathsEqual(normalized, root)) return true;
  return normalized.startsWith(root.endsWith('/') ? root : '$root/');
}

/// Longest workspace-folder path that contains [path].
String? owningWorkspaceFolderForPath(
  List<WorkspaceFolder> folders,
  String path,
) {
  final normalized = normalizeWorkspacePath(path.trim());
  if (normalized.isEmpty) return null;

  String? bestPath;
  var bestLen = -1;
  for (final folder in folders) {
    final root = normalizeWorkspacePath(folder.path);
    if (root.isEmpty || !workspacePathUnderFolder(normalized, folder.path)) {
      continue;
    }
    if (root.length > bestLen) {
      bestPath = folder.path;
      bestLen = root.length;
    }
  }
  return bestPath;
}

/// Git repo path to load after the tools plane switches to [activeTargetId].
String worktreeRepoPathForToolsTarget({
  required List<WorkspaceFolder> folders,
  required String activeTargetId,
  required String cwd,
  required String cubitRepoPath,
  String? sessionPrimaryPath,
  String? fallbackRepoPath,
}) {
  if (folders.isEmpty) {
    final fallback = fallbackRepoPath?.trim() ?? '';
    return fallback.isNotEmpty ? fallback : cwd;
  }

  String? folderOnTarget(String folderPath) {
    for (final folder in folders) {
      if (workspacePathsEqual(folder.path, folderPath) &&
          folder.targetId == activeTargetId) {
        return folder.path;
      }
    }
    return null;
  }

  String? repoForPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;
    final owner = owningWorkspaceFolderForPath(folders, trimmed);
    if (owner != null) {
      final onTarget = folderOnTarget(owner);
      if (onTarget != null) return onTarget;
    }
    return folderOnTarget(trimmed);
  }

  for (final candidate in [cubitRepoPath, cwd, sessionPrimaryPath ?? '']) {
    final repo = repoForPath(candidate);
    if (repo != null) return repo;
  }

  for (final folder in folders) {
    if (folder.targetId == activeTargetId) return folder.path;
  }

  final fallback = fallbackRepoPath?.trim() ?? '';
  if (fallback.isNotEmpty) return fallback;
  return folders.first.path;
}

/// All `workspaces` keys a CLI may use for [path] in metadata JSON.
///
/// On Windows, CLIs may run natively (`C:\foo`, `C:/foo`) or under WSL
/// (`/mnt/c/foo`). Returns every common variant so workspace trust matches
/// either runtime.
Iterable<String> workspaceMetadataKeys(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return const [];

  if (!Platform.isWindows) {
    return [normalizeWorkspacePath(path)];
  }

  return _windowsWorkspaceMetadataKeys(trimmed, path);
}

Set<String> _windowsWorkspaceMetadataKeys(String trimmed, String original) {
  final keys = <String>{};

  void addWindowsPathKeys(String windowsPath) {
    final norm = p.normalize(windowsPath);
    if (norm.isEmpty) return;
    keys.add(norm);
    final forward = norm.replaceAll(r'\', '/');
    keys.add(forward);
    keys.add(forward.replaceAll('/', r'\'));
    final wsl = LaunchCommandBuilder.windowsPathToWsl(norm);
    if (wsl != null) {
      keys.add(p.Context(style: p.Style.posix).normalize(wsl));
    }
  }

  void addPosixPathKeys(String posixPath) {
    final norm = p.Context(style: p.Style.posix).normalize(posixPath);
    if (norm.isEmpty) return;
    keys.add(norm);
    final windows = LaunchCommandBuilder.wslPathToWindows(norm);
    if (windows != null) {
      addWindowsPathKeys(windows);
    }
  }

  if (trimmed.startsWith('/') && !trimmed.startsWith('//')) {
    addPosixPathKeys(trimmed);
  } else {
    addWindowsPathKeys(trimmed);
  }

  final normalized = normalizeWorkspacePath(original);
  if (normalized.startsWith('/')) {
    addPosixPathKeys(normalized);
  } else if (normalized.isNotEmpty) {
    addWindowsPathKeys(normalized);
  }

  return keys;
}
