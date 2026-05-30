import 'dart:io';

/// Known npm install locations on macOS when GUI apps have a sparse PATH.
abstract final class MacOsNpmPathCandidates {
  MacOsNpmPathCandidates._();

  static List<String> paths() {
    if (Platform.isWindows || !Platform.isMacOS) return const [];
    final home = Platform.environment['HOME'];
    return [
      '/opt/homebrew/bin/npm',
      '/usr/local/bin/npm',
      if (home != null) '$home/.local/bin/npm',
    ];
  }

  static String? firstExisting() {
    for (final path in paths()) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }
}
