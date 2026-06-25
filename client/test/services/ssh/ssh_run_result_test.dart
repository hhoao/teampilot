import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ssh/ssh_run_result.dart';

SSHRunResult _result({
  int? exitCode,
  SSHSessionExitSignal? exitSignal,
  String stdout = '',
  String stderr = '',
}) {
  return SSHRunResult(
    output: Uint8List(0),
    stdout: Uint8List.fromList(stdout.codeUnits),
    stderr: Uint8List.fromList(stderr.codeUnits),
    exitCode: exitCode,
    exitSignal: exitSignal,
  );
}

void main() {
  test('null exitCode without signal is success', () {
    expect(sshRunSucceeded(_result()), isTrue);
    expect(sshRunFailed(_result()), isFalse);
  });

  test('zero exitCode is success', () {
    expect(sshRunSucceeded(_result(exitCode: 0)), isTrue);
  });

  test('non-zero exitCode is failure', () {
    expect(sshRunSucceeded(_result(exitCode: 1, stderr: 'denied')), isFalse);
    expect(sshRunFailureLabel(_result(exitCode: 127)), '127');
    expect(sshRunOutputDetail(_result(exitCode: 1, stderr: 'denied')), 'denied');
  });

  test('exitSignal is failure even when exitCode is null', () {
    final signal = SSHSessionExitSignal(
      signalName: 'SIGKILL',
      coreDumped: false,
      errorMessage: '',
      languageTag: '',
    );
    expect(sshRunSucceeded(_result(exitSignal: signal)), isFalse);
    expect(sshRunFailureLabel(_result(exitSignal: signal)), 'signal SIGKILL');
  });
}
