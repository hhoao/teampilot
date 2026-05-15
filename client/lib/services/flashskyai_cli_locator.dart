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

Future<ProcessResult> _flashskyDefaultProcessRun(
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

/// Resolves the absolute path of the `flashskyai` CLI executable on PATH.
///
/// GUI launches (e.g. AppImage from a file manager) often inherit a minimal PATH
/// that omits entries from `~/.bashrc` / `~/.zshrc`. When the fast [`which`]
/// lookup misses, Unix builds fall back to an interactive login shell so the
/// same PATH a terminal would see is used.
///
/// Returns null when not installed or every lookup fails.
class FlashskyaiCliLocator {
  const FlashskyaiCliLocator._();

  static const _loginShellLookupCommand = 'command -v flashskyai';

  static Future<String?> locate({
    ProcessRunner runner = _flashskyDefaultProcessRun,
  }) async {
    final cmd = Platform.isWindows ? 'where' : 'which';
    try {
      final result = await runner(cmd, ['flashskyai']);
      if (result.exitCode == 0) {
        final located = _firstStdoutLine(result.stdout);
        if (located != null) return located;
      }
      return _locateWithShellFallback(runner);
    } on ProcessException catch (error, stackTrace) {
      Logger().w('Failed to locate flashskyai: $error', stackTrace: stackTrace);
      return _locateWithShellFallback(runner);
    } on Object catch (error, stackTrace) {
      Logger().w('Failed to locate flashskyai: $error', stackTrace: stackTrace);
      return null;
    }
  }

  static Future<String?> _locateWithShellFallback(ProcessRunner runner) async {
    if (Platform.isWindows) {
      return _locateInWsl(runner);
    }
    if (Platform.isLinux || Platform.isMacOS) {
      return _locateInLoginShell(runner);
    }
    return null;
  }

  /// Resolves `flashskyai` using the user's login shell profile (bashrc/zshrc).
  static Future<String?> _locateInLoginShell(ProcessRunner runner) async {
    for (final shell in const ['bash', 'zsh']) {
      final located = await _tryLoginShellLookup(runner, shell);
      if (located != null) return located;
    }
    return null;
  }

  static Future<String?> _tryLoginShellLookup(
    ProcessRunner runner,
    String shell,
  ) async {
    try {
      final result = await runner(
        shell,
        ['-ilc', _loginShellLookupCommand],
        stdoutEncoding: latin1,
        stderrEncoding: latin1,
      );
      if (result.exitCode != 0) return null;
      return _firstStdoutLine(result.stdout);
    } on Object catch (error, stackTrace) {
      Logger().w(
        'Failed to locate flashskyai via $shell login shell: $error',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  static Future<String?> _locateInWsl(ProcessRunner runner) async {
    try {
      final result = await runner(
        'wsl.exe',
        ['bash', '-ilc', _loginShellLookupCommand],
        stdoutEncoding: latin1,
        stderrEncoding: latin1,
      );
      if (result.exitCode != 0) return null;
      final located = _wslStdoutExecutablePath(result.stdout);
      if (located == null) return null;
      return 'wsl.exe $located';
    } on Object catch (error, stackTrace) {
      Logger().w(
        'Failed to locate flashskyai in WSL: $error',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  static String? _firstStdoutLine(Object? stdoutValue) {
    final text = _stdoutAsString(stdoutValue);
    if (text == null) return null;
    final firstLine = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return null;
    return firstLine;
  }

  /// Picks the resolved POSIX path from `wsl.exe` stdout, skipping known noise
  /// lines (some WSL builds have been observed to print CLI hints on stdout).
  static String? _wslStdoutExecutablePath(Object? stdoutValue) {
    final text = _stdoutAsString(stdoutValue);
    if (text == null) return null;
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (_looksLikeWslCliNoiseLine(line)) continue;
      if (line.startsWith('/') && line.contains('flashskyai')) {
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
