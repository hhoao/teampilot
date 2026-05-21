import 'dart:io';

import 'package:path/path.dart' as p;

import '../services/app_storage.dart';
import '../services/launch_command_builder.dart';
import '../services/runtime_storage_context.dart';

/// Normalizes a filesystem path for stable comparison and storage.
///
/// Remote/SSH paths starting with `~` are kept as trimmed text only.
/// On Windows + WSL storage, Windows picker paths are converted to `/mnt/...`.
String normalizeProjectPath(String path) {
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

bool projectPathsEqual(String a, String b) {
  return normalizeProjectPath(a) == normalizeProjectPath(b);
}

bool projectPathsContains(Iterable<String> paths, String target) {
  final normalized = normalizeProjectPath(target);
  for (final existing in paths) {
    if (normalizeProjectPath(existing) == normalized) return true;
  }
  return false;
}
