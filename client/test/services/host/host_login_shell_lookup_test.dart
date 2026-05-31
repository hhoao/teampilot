import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_login_shell_lookup.dart';

void main() {
  test('commandForExecutable', () {
    expect(
      HostLoginShellLookup.commandForExecutable('npm'),
      'command -v npm',
    );
  });

  test('locateViaLoginShells returns first successful shell line', () async {
    var bashCalls = 0;
    final located = await HostLoginShellLookup.locateViaLoginShells(
      innerCommand: 'command -v npm',
      runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
        if (executable == 'bash') {
          bashCalls++;
          return ProcessResult(0, 0, '/opt/homebrew/bin/npm\n', '');
        }
        return ProcessResult(0, 1, '', '');
      },
    );
    expect(located, '/opt/homebrew/bin/npm');
    expect(bashCalls, 1);
  });

  test('locateViaWsl prefixes wsl.exe when line matches', () async {
    final located = await HostLoginShellLookup.locateViaWsl(
      innerCommand: 'command -v claude',
      pickLine: (line) =>
          line.startsWith('/') && line.contains('claude') ? line : null,
      runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
        expect(executable, 'wsl.exe');
        return ProcessResult(
          0,
          0,
          'wsl: warning\n/home/user/.local/bin/claude\n',
          '',
        );
      },
    );
    expect(located, '/home/user/.local/bin/claude');
  });
}
