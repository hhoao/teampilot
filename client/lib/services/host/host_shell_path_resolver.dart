import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../utils/logging/logger.dart';

/// Starts a probe shell whose handle stays reachable, so a hung rc plugin can
/// be killed instead of leaking an orphaned interactive shell per app run.
typedef ShellPathProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

Future<Process> defaultShellPathProcessStart(
  String executable,
  List<String> arguments,
) {
  return Process.start(executable, arguments);
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
  /// Entries containing whitespace are dropped — fish joins `$PATH` with
  /// spaces, so its output degrades to null (falling through to zsh/bash)
  /// instead of installing a bogus directory.
  /// Returns null when nothing valid remains.
  static String? parseMarkerOutput(Object? stdout) {
    if (stdout is! String) return null;
    final index = stdout.lastIndexOf(marker);
    if (index < 0) return null;
    var value = stdout.substring(index + marker.length);
    final lineBreak = RegExp(r'[\r\n]').firstMatch(value);
    if (lineBreak != null) {
      value = value.substring(0, lineBreak.start);
    }
    final entries = value
        .split(':')
        .map((entry) => entry.trim())
        .where(
          (entry) => entry.startsWith('/') && !entry.contains(RegExp(r'\s')),
        )
        .toList();
    return entries.isEmpty ? null : entries.join(':');
  }

  /// Kick off resolution once; later calls are no-ops.
  static Future<void> warmup({
    ShellPathProcessStarter starter = defaultShellPathProcessStart,
  }) {
    if (_resolved) return Future.value();
    return resolve(starter: starter);
  }

  static Future<String?> resolve({
    ShellPathProcessStarter starter = defaultShellPathProcessStart,
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
      resolved = await _probeShell(shell, starter, timeout);
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
    ShellPathProcessStarter starter,
    Duration timeout,
  ) async {
    final Process process;
    try {
      // argv goes straight to `<shell> -c`. `$PATH` must expand in the CHILD
      // shell, so build the string via concatenation to dodge Dart `$`
      // interpolation: literal output is `printf "%s" "__TP_PATH__$PATH"`.
      final innerCommand = 'printf "%s" "$marker' r'$PATH"';
      process = await starter(shell, ['-ilc', innerCommand]);
    } on Object catch (error) {
      appLogger.w('[shell-path] $shell -ilc failed to start: $error');
      return null;
    }

    final output = BytesBuilder(copy: false);
    final drained = Completer<void>();
    final outSub = process.stdout.listen(
      output.add,
      onDone: drained.complete,
      onError: (Object _) => drained.complete(),
      cancelOnError: true,
    );
    final errSub = process.stderr.listen(
      (_) {},
      onError: (Object _) {},
      cancelOnError: true,
    );

    var timedOut = false;
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      exitCode = -1;
    }
    if (timedOut) {
      appLogger.w('[shell-path] $shell -ilc timed out; killing pid '
          '${process.pid}');
      unawaited(outSub.cancel());
      unawaited(errSub.cancel());
      process.kill();
      return null;
    }
    // Drain the pipes after a normal exit so late output can't deadlock.
    await drained.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    unawaited(outSub.cancel());
    unawaited(errSub.cancel());
    if (exitCode != 0) return null;
    return parseMarkerOutput(utf8.decode(output.toBytes(), allowMalformed: true));
  }
}
