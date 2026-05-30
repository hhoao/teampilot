import 'dart:convert';
import 'dart:io';

import 'host_executable_locator.dart';

/// Login-shell and WSL fallbacks when bare `which` / `where` misses (sparse PATH).
abstract final class HostLoginShellLookup {
  HostLoginShellLookup._();

  static const posixShells = ['bash', 'zsh'];

  static String commandForExecutable(String name) => 'command -v $name';

  /// Tries `bash` / `zsh` with `-ilc [innerCommand]`; returns first stdout line.
  static Future<String?> locateViaLoginShells({
    required Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Encoding? stdoutEncoding,
      Encoding? stderrEncoding,
    })
    runner,
    required String innerCommand,
  }) async {
    for (final shell in posixShells) {
      try {
        final result = await runner(
          shell,
          ['-ilc', innerCommand],
          stdoutEncoding: latin1,
          stderrEncoding: latin1,
        );
        if (result.exitCode != 0) continue;
        final line = HostExecutableLocator.parseFirstStdoutLine(result.stdout);
        if (line != null && line.isNotEmpty) return line;
      } on Object {
        continue;
      }
    }
    return null;
  }

  /// Windows: `wsl.exe bash -ilc` then [pickLine] on stdout lines.
  static Future<String?> locateViaWsl({
    required Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Encoding? stdoutEncoding,
      Encoding? stderrEncoding,
    })
    runner,
    required String innerCommand,
    required String? Function(String line) pickLine,
  }) async {
    try {
      final result = await runner(
        'wsl.exe',
        ['bash', '-ilc', innerCommand],
        stdoutEncoding: latin1,
        stderrEncoding: latin1,
      );
      if (result.exitCode != 0) return null;
      final text = _stdoutAsString(result.stdout);
      if (text == null) return null;
      for (final raw in text.split(RegExp(r'\r?\n'))) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        if (_looksLikeWslCliNoiseLine(line)) continue;
        final picked = pickLine(line);
        if (picked != null) return picked;
      }
      return null;
    } on Object {
      return null;
    }
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
