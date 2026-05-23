import 'dart:convert';
import 'dart:io';

import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;

typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Encoding? stdoutEncoding,
      Encoding? stderrEncoding,
    });

Future<ProcessResult> cliToolDefaultProcessRun(
  String executable,
  List<String> arguments, {
  Encoding? stdoutEncoding,
  Encoding? stderrEncoding,
}) {
  return Process.run(
    executable,
    arguments,
    stdoutEncoding: stdoutEncoding ?? systemEncoding,
    stderrEncoding: stderrEncoding ?? systemEncoding,
  );
}

/// Resolves a CLI executable on PATH, with login-shell fallback for GUI
/// launches that start with a sparse environment.
class CliToolLocator {
  const CliToolLocator(this.executableName);

  final String executableName;

  String get lookupCommand => 'command -v $executableName';

  Future<String?> locate({
    ProcessRunner runner = cliToolDefaultProcessRun,
    bool? isWindowsOverride,
  }) async {
    final isWindows = isWindowsOverride ?? Platform.isWindows;
    final cmd = isWindows ? 'where' : 'which';
    try {
      final result = await runner(cmd, [executableName]);
      if (result.exitCode == 0) {
        final located = parsePathLookupOutput(
          result.stdout,
          isWindows: isWindows,
        );
        if (located != null) return located;
      }
      return _locateWithShellFallback(runner, isWindows: isWindows);
    } on ProcessException catch (error, stackTrace) {
      Logger().w(
        'Failed to locate $executableName: $error',
        stackTrace: stackTrace,
      );
      return _locateWithShellFallback(runner, isWindows: isWindows);
    } on Object catch (error, stackTrace) {
      Logger().w(
        'Failed to locate $executableName: $error',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<String?> _locateWithShellFallback(
    ProcessRunner runner, {
    required bool isWindows,
  }) async {
    if (isWindows) {
      return _locateInWsl(runner);
    }
    if (Platform.isLinux || Platform.isMacOS) {
      return _locateInLoginShell(runner);
    }
    return null;
  }

  Future<String?> _locateInLoginShell(ProcessRunner runner) async {
    for (final shell in const ['bash', 'zsh']) {
      final located = await _tryLoginShellLookup(runner, shell);
      if (located != null) return located;
    }
    return null;
  }

  Future<String?> _tryLoginShellLookup(
    ProcessRunner runner,
    String shell,
  ) async {
    try {
      final result = await runner(
        shell,
        ['-ilc', lookupCommand],
        stdoutEncoding: latin1,
        stderrEncoding: latin1,
      );
      if (result.exitCode != 0) return null;
      return parseFirstStdoutLine(result.stdout);
    } on Object catch (error, stackTrace) {
      Logger().w(
        'Failed to locate $executableName via $shell login shell: $error',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<String?> _locateInWsl(ProcessRunner runner) async {
    try {
      final result = await runner(
        'wsl.exe',
        ['bash', '-ilc', lookupCommand],
        stdoutEncoding: latin1,
        stderrEncoding: latin1,
      );
      if (result.exitCode != 0) return null;
      final located = _wslStdoutExecutablePath(result.stdout);
      if (located == null) return null;
      return 'wsl.exe $located';
    } on Object catch (error, stackTrace) {
      Logger().w(
        'Failed to locate $executableName in WSL: $error',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  static List<String> parseStdoutLines(Object? stdoutValue) {
    final text = _stdoutAsString(stdoutValue);
    if (text == null) return const [];
    return text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  static String? parseFirstStdoutLine(Object? stdoutValue) {
    final lines = parseStdoutLines(stdoutValue);
    if (lines.isEmpty) return null;
    return lines.first;
  }

  /// Picks a Windows-native executable from `where` output. npm global bins
  /// list a shell shim before `.cmd`; flutter_pty cannot spawn the shim.
  static String? parsePathLookupOutput(
    Object? stdoutValue, {
    required bool isWindows,
  }) {
    final lines = parseStdoutLines(stdoutValue);
    if (lines.isEmpty) return null;
    if (!isWindows) return lines.first;
    return preferWindowsNativeExecutable(lines) ?? lines.first;
  }

  static String? preferWindowsNativeExecutable(List<String> candidates) {
    for (final ext in const ['.exe', '.cmd', '.bat', '.com']) {
      for (final candidate in candidates) {
        if (p.extension(candidate).toLowerCase() == ext) {
          return candidate;
        }
      }
    }
    return null;
  }

  /// Normalizes npm/global shims and other extensionless paths for PTY spawn.
  static String resolveSpawnExecutable(String executable) {
    if (!Platform.isWindows) return executable;
    if (!_looksLikePath(executable)) return executable;

    final ext = p.extension(executable).toLowerCase();
    if (const {'.exe', '.cmd', '.bat', '.com'}.contains(ext)) {
      return executable;
    }

    final cmdPath = '$executable.cmd';
    if (File(cmdPath).existsSync()) return cmdPath;

    final exePath = '$executable.exe';
    if (File(exePath).existsSync()) return exePath;

    return executable;
  }

  static bool _looksLikePath(String executable) {
    return executable.contains('/') ||
        executable.contains(r'\') ||
        executable.contains(':');
  }

  String? _wslStdoutExecutablePath(Object? stdoutValue) {
    final text = _stdoutAsString(stdoutValue);
    if (text == null) return null;
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (_looksLikeWslCliNoiseLine(line)) continue;
      if (line.startsWith('/') && line.contains(executableName)) {
        return line;
      }
    }
    return null;
  }

  static bool _looksLikeWslCliNoiseLine(String line) {
    final lower = line.toLowerCase();
    return lower.startsWith('wsl:') || lower.startsWith('wsl ');
  }

  static String? _stdoutAsString(Object? stdoutValue) {
    if (stdoutValue is String) return stdoutValue;
    if (stdoutValue is List<int>) {
      return utf8.decode(stdoutValue, allowMalformed: true);
    }
    return null;
  }
}
