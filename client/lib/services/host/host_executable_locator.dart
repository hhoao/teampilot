import 'dart:convert';

import 'package:path/path.dart' as p;

import 'host_execution_environment.dart';

/// Resolves executables on PATH (`where` / `which`) for the current host.
final class HostExecutableLocator {
  const HostExecutableLocator(this.environment);

  final HostExecutionEnvironment environment;

  String get whichCommand => environment.isWindowsHost ? 'where' : 'which';

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

  static String? _stdoutAsString(Object? stdoutValue) {
    if (stdoutValue is String) return stdoutValue;
    if (stdoutValue is List<int>) {
      return utf8.decode(stdoutValue, allowMalformed: true);
    }
    return null;
  }
}
