import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import '../../utils/logging/logger.dart';

typedef ShellPathProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Encoding? stdoutEncoding,
      Encoding? stderrEncoding,
    });

Future<ProcessResult> defaultShellPathProcessRun(
  String executable,
  List<String> arguments, {
  Encoding? stdoutEncoding,
  Encoding? stderrEncoding,
}) {
  return Process.run(
    executable,
    arguments,
    stdoutEncoding: stdoutEncoding ?? latin1,
    stderrEncoding: stderrEncoding ?? latin1,
  );
}

/// Resolves the user's login-shell PATH once per process so local PTY children
/// can run CLIs whose shebangs (`#!/usr/bin/env node`) need Homebrew /
/// version-manager / ~/.local/bin directories that GUI launches never inherit.
///
/// `-ilc` shells may print rc-file noise before command output (prompts, nvm
/// banners, escape sequences), so the PATH is captured behind a [marker] and
/// extracted from the last occurrence.
abstract final class HostShellPathResolver {
  HostShellPathResolver._();

  /// Output sentinel printed in front of the expanded `$PATH`.
  static const String marker = '__TP_PATH__';

  static const Duration defaultPerShellTimeout = Duration(seconds: 5);

  static const _fallbackShells = ['zsh', 'bash'];

  static bool _resolved = false;
  static String? _cachedPath;

  /// Test-only seam: overrides where `$SHELL` is read from.
  @visibleForTesting
  static String Function()? debugShellOverride;

  /// Test-only seam: forces/clears the cached resolution result.
  @visibleForTesting
  static void debugSetCachedPath(String? path) {
    _cachedPath = path;
    _resolved = true;
  }

  static String? get cachedPath => _cachedPath;

  static void resetForTest() {
    _resolved = false;
    _cachedPath = null;
    debugShellOverride = null;
  }

  static bool _isPosixDesktop() => Platform.isMacOS || Platform.isLinux;

  static List<String> shellCandidates() {
    final shell =
        debugShellOverride?.call() ?? Platform.environment['SHELL'] ?? '';
    final segments = shell.split('/');
    final basename = segments.isEmpty ? '' : segments.last.trim();
    return [
      if (basename.isNotEmpty && !_fallbackShells.contains(basename))
        basename,
      ..._fallbackShells,
    ];
  }

  static List<String> fallbackCandidateDirs() {
    final home = Platform.environment['HOME']?.trim();
    return [
      '/opt/homebrew/bin',
      '/usr/local/bin',
      if (home != null && home.isNotEmpty) '$home/.local/bin',
    ];
  }

  /// Extracts the PATH from shell stdout: everything after the LAST [marker],
  /// truncated at the first CR/LF (PATH cannot contain newlines), trimmed.
  /// Returns null when the marker is missing or the value is empty or has no
  /// absolute entry.
  static String? parseMarkerOutput(Object? stdout) {
    if (stdout is! String) return null;
    final index = stdout.lastIndexOf(marker);
    if (index < 0) return null;
    var value = stdout.substring(index + marker.length);
    final lineBreak = RegExp(r'[\r\n]').firstMatch(value);
    if (lineBreak != null) {
      value = value.substring(0, lineBreak.start);
    }
    value = value.trim();
    if (value.isEmpty) return null;
    final hasAbsoluteEntry = value.split(':').any((entry) => entry.startsWith('/'));
    return hasAbsoluteEntry ? value : null;
  }

  /// Kick off resolution once; later calls are no-ops.
  static Future<void> warmup({
    ShellPathProcessRunner runner = defaultShellPathProcessRun,
  }) {
    if (_resolved) return Future.value();
    return resolve(runner: runner);
  }

  static Future<String?> resolve({
    ShellPathProcessRunner runner = defaultShellPathProcessRun,
    Duration timeout = defaultPerShellTimeout,
    bool? posixPlatformOverride,
  }) async {
    if (_resolved) return _cachedPath;
    final posix = posixPlatformOverride ?? _isPosixDesktop();
    if (!posix) {
      _cachedPath = null;
      _resolved = true;
      return null;
    }
    String? resolved;
    for (final shell in shellCandidates()) {
      resolved = await _probeShell(shell, runner, timeout);
      if (resolved != null) break;
    }
    _cachedPath = resolved;
    _resolved = true;
    if (resolved == null) {
      appLogger.w(
        '[shell-path] login-shell PATH resolution failed; PTY spawns will '
        'append known candidate dirs instead',
      );
    } else {
      appLogger.i('[shell-path] login-shell PATH resolved');
    }
    return resolved;
  }

  static Future<String?> _probeShell(
    String shell,
    ShellPathProcessRunner runner,
    Duration timeout,
  ) async {
    try {
      // argv goes straight to `<shell> -c`. `$PATH` must expand in the CHILD
      // shell, so build the string via concatenation to dodge Dart `$`
      // interpolation: literal output is `printf "%s" "__TP_PATH__$PATH"`.
      final innerCommand = 'printf "%s" "$marker' r'$PATH"';
      final result = await runner(shell, [
        '-ilc',
        innerCommand,
      ]).timeout(timeout);
      if (result.exitCode != 0) return null;
      return parseMarkerOutput(result.stdout);
    } on TimeoutException {
      appLogger.w('[shell-path] $shell -ilc timed out');
      return null;
    } on Object catch (error) {
      appLogger.w('[shell-path] $shell -ilc failed: $error');
      return null;
    }
  }
}
