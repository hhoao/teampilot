import 'dart:io';

import 'package:path/path.dart' as p;

import '../services/storage/app_storage.dart';
import '../services/session/launch_command_builder.dart';
import '../services/storage/runtime_storage_context.dart';

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
      RuntimeStorageContext.isInstalled &&
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
