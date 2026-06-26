import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves the user login shell for the workspace panel (not agent CLIs).
abstract final class WorkspaceInteractiveShell {
  static String executable() {
    if (Platform.isWindows) {
      final comspec = Platform.environment['COMSPEC']?.trim() ?? '';
      if (comspec.isNotEmpty) return comspec;
      return r'cmd.exe';
    }
    final shell = Platform.environment['SHELL']?.trim() ?? '';
    if (shell.isNotEmpty) return shell;
    return '/bin/bash';
  }

  /// Candidate login shells for the IDEA-style new-session menu.
  static List<String> discoverShellPaths() {
    if (Platform.isWindows) {
      return [executable()];
    }
    final seen = <String>{};
    final paths = <String>[];
    void add(String? raw) {
      final trimmed = raw?.trim() ?? '';
      if (trimmed.isEmpty || seen.contains(trimmed)) return;
      seen.add(trimmed);
      paths.add(trimmed);
    }

    add(Platform.environment['SHELL']);
    for (final candidate in [
      '/bin/bash',
      '/usr/bin/bash',
      '/bin/zsh',
      '/usr/bin/zsh',
    ]) {
      add(candidate);
    }
    if (paths.isEmpty) add('/bin/bash');
    return paths;
  }

  static String menuLabelFor(String shellPath) {
    final trimmed = shellPath.trim();
    if (trimmed.isEmpty) return 'shell';
    return '${p.basename(trimmed)} ($trimmed)';
  }

  static List<String> launchArguments(String executable) {
    if (Platform.isWindows) return const [];
    final name = p.basename(executable);
    if (name == 'bash' || name == 'zsh') return const ['-l'];
    return const [];
  }
}
