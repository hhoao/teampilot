import 'dart:io';

import 'package:path/path.dart' as p;

typedef ProcessRunner = Future<void> Function(String exe, List<String> args);

/// Opens a directory in the OS file manager. Desktop-only; the caller hides the
/// affordance on remote (SSH) storage backends.
class SystemFolderOpener {
  SystemFolderOpener({
    bool? isMacOS,
    bool? isWindows,
    bool? isLinux,
    ProcessRunner? runner,
  })  : _isMacOS = isMacOS ?? Platform.isMacOS,
        _isWindows = isWindows ?? Platform.isWindows,
        _isLinux = isLinux ?? Platform.isLinux,
        _runner = runner ?? _defaultRunner;

  final bool _isMacOS;
  final bool _isWindows;
  final bool _isLinux;
  final ProcessRunner _runner;

  static Future<void> _defaultRunner(String exe, List<String> args) async {
    await Process.run(exe, args);
  }

  Future<void> reveal(String path) async {
    final target = path.trim();
    if (target.isEmpty) return;
    final String exe;
    if (_isMacOS) {
      exe = 'open';
    } else if (_isWindows) {
      exe = 'explorer';
    } else if (_isLinux) {
      exe = 'xdg-open';
    } else {
      exe = 'xdg-open';
    }
    await _runner(exe, [target]);
  }

  /// Parent directory to reveal when [filePath] is a file.
  static String revealPathForFile(String filePath) {
    final trimmed = filePath.trim();
    if (trimmed.isEmpty) return trimmed;
    return p.dirname(trimmed);
  }
}
