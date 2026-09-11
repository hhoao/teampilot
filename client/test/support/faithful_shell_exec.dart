import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

/// Runs a probe command through a real local POSIX shell so redirections,
/// `||` short-circuits, and exit codes behave exactly as they would on the
/// remote host.
///
/// Hand-rolled mocks that return a canned path (e.g. `'/usr/bin/git\n'`)
/// can silently paper over probe bugs: a command like
/// `command -v git >/dev/null 2>&1 || which git` actually produces *empty*
/// stdout when git exists, and only a real shell reproduces that.
///
/// `/bin/sh` is the remote-host stand-in on POSIX hosts; Windows has none,
/// so we fall back to `sh`/`bash` from Git for Windows (CI runners always
/// have it on PATH — their default shell is Git bash).
///
/// [path] simulates the remote host's PATH. It is assigned INSIDE the shell
/// command (`PATH=…; cmd`), not via the child environment: bash rebuilds a
/// default PATH at startup when the inherited one looks unusable (msys bash
/// on Windows repopulates PATH with its own mingw64/bin, where git lives),
/// but an explicit assignment in the script body cannot be self-healed.
Future<SSHRunResult> faithfulShellExec(String command, {String? path}) async {
  final shell = _posixShell;
  final result = await Process.run(shell, [
    '-c',
    [if (path != null) "PATH='$path'; " else '', command].join(''),
  ]);
  final stdoutBytes = utf8.encode(result.stdout as String);
  final stderrBytes = utf8.encode(result.stderr as String);
  return SSHRunResult(
    output: utf8.encode('${result.stdout}${result.stderr}'),
    stdout: stdoutBytes,
    stderr: stderrBytes,
    exitCode: result.exitCode,
    exitSignal: null,
  );
}

/// A real POSIX shell available on this host, resolved once per process.
String? _cachedShell;

String get _posixShell => _cachedShell ??= _resolvePosixShell();

String _resolvePosixShell() {
  const candidates = ['/bin/sh', 'sh', 'bash'];
  for (final candidate in candidates) {
    // Bare names resolve through PATH; absolute paths must exist.
    if (candidate.contains('/')) {
      if (File(candidate).existsSync()) return candidate;
    } else {
      return candidate;
    }
  }
  return 'bash';
}
