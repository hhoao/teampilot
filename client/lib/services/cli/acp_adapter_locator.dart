import 'dart:io';

import '../storage/app_paths.dart';

/// Resolves an ACP adapter binary without installing anything.
///
/// On Windows: walks `PATH`/`Path` (semicolon-separated) and `PATHEXT`.
/// On Unix: `PATH` (`:`), then `~/.local/bin`, then the TeamPilot node prefix,
/// else the bare [name].
String locateAcpAdapter({
  required String name,
  Map<String, String>? environment,
  bool Function(String path)? fileExists,
  bool? isWindows,
}) {
  final windows = isWindows ?? Platform.isWindows;
  final env = environment ?? Platform.environment;
  final exists = fileExists ?? (path) => File(path).existsSync();

  if (windows) {
    final pathVar = env['PATH'] ?? env['Path'] ?? '';
    final pathEntries = pathVar.split(';');
    final pathext = (env['PATHEXT'] ?? '.EXE;.CMD;.BAT;.COM')
        .split(';')
        .where((e) => e.isNotEmpty);

    for (final dir in pathEntries) {
      if (dir.isEmpty) continue;
      final base = _joinWindows(dir, name);
      if (exists(base)) return base;
      for (final ext in pathext) {
        final candidate = '$base$ext';
        if (exists(candidate)) return candidate;
      }
    }
    return name;
  }

  final pathEntries = (env['PATH'] ?? '').split(':');
  for (final dir in pathEntries) {
    if (dir.isEmpty) continue;
    if (exists('$dir/$name')) return '$dir/$name';
  }
  final home = env['HOME'];
  if (home != null && home.isNotEmpty) {
    final local = '$home/.local/bin/$name';
    if (exists(local)) return local;
    final toolchain =
        '$home/.local/share/${AppPaths.teampilotAppDataDirName}/toolchain/node/current/bin/$name';
    if (exists(toolchain)) return toolchain;
  }
  return name;
}

String _joinWindows(String dir, String name) {
  if (dir.endsWith(r'\') || dir.endsWith('/')) {
    return '$dir$name';
  }
  return '$dir\\$name';
}
