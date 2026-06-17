import 'dart:io';

import 'package:path/path.dart' as p;

typedef ProcessStarter =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      bool runInShell,
    });

/// Opens a system terminal whose working directory is [directoryPath].
///
/// Desktop-local only; callers should hide the affordance on SSH / web builds.
class SystemTerminalOpener {
  SystemTerminalOpener({
    bool? isMacOS,
    bool? isWindows,
    bool? isLinux,
    ProcessStarter? starter,
  }) : _isMacOS = isMacOS ?? Platform.isMacOS,
       _isWindows = isWindows ?? Platform.isWindows,
       _isLinux = isLinux ?? Platform.isLinux,
       _starter =
           starter ??
           ((exe, args, {workingDirectory, runInShell = false}) => Process.run(
             exe,
             args,
             workingDirectory: workingDirectory,
             runInShell: runInShell,
           ));

  final bool _isMacOS;
  final bool _isWindows;
  final bool _isLinux;
  final ProcessStarter _starter;

  Future<bool> openAt(String directoryPath) async {
    final target = await _resolveDirectory(directoryPath);
    if (target == null || target.isEmpty) return false;

    if (_isLinux) {
      return _tryLinux(target);
    }
    if (_isMacOS) {
      return _tryMacOS(target);
    }
    if (_isWindows) {
      return _tryWindows(target);
    }
    return false;
  }

  Future<String?> _resolveDirectory(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;
    try {
      final type = await FileSystemEntity.type(trimmed, followLinks: false);
      if (type == FileSystemEntityType.directory) return trimmed;
      if (type == FileSystemEntityType.file) return p.dirname(trimmed);
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<bool> _tryLinux(String target) async {
    final attempts = <(String, List<String>)>[
      ('gnome-terminal', ['--working-directory', target]),
      ('konsole', ['--workdir', target]),
      ('xfce4-terminal', ['--working-directory', target]),
      ('x-terminal-emulator', [
        '-e',
        'bash',
        '-lc',
        'cd ${_shellQuote(target)}; exec bash',
      ]),
      ('xterm', ['-e', 'bash', '-lc', 'cd ${_shellQuote(target)}; exec bash']),
    ];
    for (final attempt in attempts) {
      if (await _run(attempt.$1, attempt.$2, target)) return true;
    }
    return false;
  }

  Future<bool> _tryMacOS(String target) async {
    final script = 'cd ${_shellQuote(target)}';
    if (await _run('open', ['-a', 'Terminal', script], target)) return true;
    return _run('osascript', [
      '-e',
      'tell application "Terminal" to do script "$script"',
    ], target);
  }

  Future<bool> _tryWindows(String target) async {
    if (await _run('wt.exe', ['-d', target], target)) return true;
    return _run('cmd', [
      '/c',
      'start',
      'cmd',
      '/k',
      'cd /d ${_windowsQuote(target)}',
    ], target);
  }

  Future<bool> _run(String exe, List<String> args, String workingDirectory) async {
    try {
      final result = await _starter(
        exe,
        args,
        workingDirectory: workingDirectory,
        runInShell: true,
      );
      return result.exitCode == 0;
    } on IOException {
      return false;
    }
  }

  static String _shellQuote(String value) {
    if (value.isEmpty) return "''";
    if (!value.contains(RegExp(r'\s'))) return value;
    return "'${value.replaceAll("'", r"'\''")}'";
  }

  static String _windowsQuote(String value) =>
      value.contains(' ') ? '"$value"' : value;
}
