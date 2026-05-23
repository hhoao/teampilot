import 'dart:convert';
import 'dart:io';

import 'package:logger/logger.dart';

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
        final located = parseFirstStdoutLine(result.stdout);
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

  static String? parseFirstStdoutLine(Object? stdoutValue) {
    final text = _stdoutAsString(stdoutValue);
    if (text == null) return null;
    final firstLine = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return null;
    return firstLine;
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
