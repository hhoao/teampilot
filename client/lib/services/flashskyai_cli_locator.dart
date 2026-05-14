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
/// Returns null when not installed or the lookup fails.
class FlashskyaiCliLocator {
  const FlashskyaiCliLocator._();

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
      if (Platform.isWindows) {
        return _locateInWsl(runner);
      }
      return null;
    } on ProcessException catch (error, stackTrace) {
      Logger().w('Failed to locate flashskyai: $error', stackTrace: stackTrace);
      if (Platform.isWindows) {
        return _locateInWsl(runner);
      }
      return null;
    } on Object catch (error, stackTrace) {
      Logger().w('Failed to locate flashskyai: $error', stackTrace: stackTrace);
      return null;
    }
  }

  static Future<String?> _locateInWsl(ProcessRunner runner) async {
    try {
      // Use bash (not sh/dash): Ubuntu WSL's ~/.profile only sources ~/.bashrc
      // when BASH_VERSION is set, so dash login shells miss PATH from ~/.bashrc.
      //
      // Use `-ilc` (interactive login): many `~/.bashrc` templates return early
      // when `$-` lacks `i`, so plain `-lc` never applies PATH exports from bashrc.
      //
      // Use Latin-1 for subprocess pipes: `wsl.exe` output is usually UTF-8, but
      // some builds mix encodings or emit non-UTF-8 bytes; strict UTF-8 decoding
      // throws [FormatException] before we can parse. Latin-1 maps every byte to
      // a code point without failure; ASCII paths stay identical to UTF-8.
      final result = await runner(
        'wsl.exe',
        ['bash', '-ilc', 'command -v flashskyai'],
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
