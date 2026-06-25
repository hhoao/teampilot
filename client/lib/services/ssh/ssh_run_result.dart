import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

/// Whether a non-interactive SSH exec completed successfully.
///
/// [SSHRunResult.exitCode] may be null when the server omits exit status; that
/// is treated as success unless [SSHRunResult.exitSignal] is set (same rule as
/// [RemoteSshStoragePathResolver]).
bool sshRunSucceeded(SSHRunResult result) {
  final code = result.exitCode;
  if (code != null && code != 0) return false;
  if (result.exitSignal != null) return false;
  return true;
}

bool sshRunFailed(SSHRunResult result) => !sshRunSucceeded(result);

/// Short label for error messages (`0`, `127`, `signal SIGKILL`, …).
String sshRunFailureLabel(SSHRunResult result) {
  final code = result.exitCode;
  if (code != null) return '$code';
  final signal = result.exitSignal;
  if (signal != null) return 'signal ${signal.signalName}';
  return 'unknown';
}

/// Best-effort stderr/stdout snippet for diagnostics.
String sshRunOutputDetail(SSHRunResult result) {
  final stderrText = utf8.decode(result.stderr, allowMalformed: true).trim();
  if (stderrText.isNotEmpty) return stderrText;
  final stdoutText = utf8.decode(result.stdout, allowMalformed: true).trim();
  if (stdoutText.isNotEmpty) return stdoutText;
  return 'no output';
}
