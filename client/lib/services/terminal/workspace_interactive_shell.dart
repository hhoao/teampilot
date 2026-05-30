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

  static List<String> launchArguments(String executable) {
    if (Platform.isWindows) return const [];
    final name = p.basename(executable);
    if (name == 'bash' || name == 'zsh') return const ['-l'];
    return const [];
  }
}
