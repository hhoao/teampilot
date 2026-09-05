import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

/// Runs a probe command through the real local `/bin/sh` so redirections,
/// `||` short-circuits, and exit codes behave exactly as they would on the
/// remote host.
///
/// Hand-rolled mocks that return a canned path (e.g. `'/usr/bin/git\n'`)
/// can silently paper over probe bugs: a command like
/// `command -v git >/dev/null 2>&1 || which git` actually produces *empty*
/// stdout when git exists, and only a real shell reproduces that.
Future<SSHRunResult> faithfulShellExec(String command, {String? path}) async {
  final result = await Process.run(
    '/bin/sh',
    ['-c', command],
    environment: path == null ? null : {'PATH': path},
  );
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
