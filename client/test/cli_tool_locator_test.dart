import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli_tool_locator.dart';

void main() {
  test('locate returns native path from PATH lookup', () async {
    final located = await const CliToolLocator('claude').locate(
      runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
        return ProcessResult(1, 0, '/opt/bin/claude\n', '');
      },
    );

    expect(located, '/opt/bin/claude');
  });

  test(
    'locate falls back to bash login shell when PATH lookup misses on Unix',
    () async {
      if (Platform.isWindows) return;
      final calls = <String>[];
      final located = await const CliToolLocator('claude').locate(
        runner:
            (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
              calls.add('$executable ${arguments.join(' ')}');
              if (executable == 'which') {
                return ProcessResult(1, 1, '', '');
              }
              if (executable == 'bash') {
                expect(arguments, ['-ilc', 'command -v claude']);
                expect(stdoutEncoding, latin1);
                return ProcessResult(
                  2,
                  0,
                  '/home/user/.local/bin/claude\n',
                  '',
                );
              }
              fail('unexpected runner call: $executable');
            },
      );

      expect(calls, ['which claude', 'bash -ilc command -v claude']);
      expect(located, '/home/user/.local/bin/claude');
    },
  );

  test(
    'parsePathLookupOutput prefers Windows-native npm shim on Windows',
    () {
      const stdout =
          r'C:\Users\alice\AppData\Roaming\npm\claude'
          '\r\n'
          r'C:\Users\alice\AppData\Roaming\npm\claude.cmd';

      expect(
        CliToolLocator.parsePathLookupOutput(stdout, isWindows: true),
        r'C:\Users\alice\AppData\Roaming\npm\claude.cmd',
      );
      expect(
        CliToolLocator.parsePathLookupOutput(stdout, isWindows: false),
        r'C:\Users\alice\AppData\Roaming\npm\claude',
      );
    },
  );

  test('locate prefers claude.cmd over npm shell shim on Windows', () async {
    final located = await const CliToolLocator('claude').locate(
      isWindowsOverride: true,
      runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
        expect(executable, 'where');
        return ProcessResult(
          1,
          0,
          r'C:\Users\alice\AppData\Roaming\npm\claude'
          '\r\n'
          r'C:\Users\alice\AppData\Roaming\npm\claude.cmd',
          '',
        );
      },
    );

    expect(located, r'C:\Users\alice\AppData\Roaming\npm\claude.cmd');
  });

  test('resolveSpawnExecutable prefers sibling .cmd on Windows', () async {
    if (!Platform.isWindows) return;

    final tempDir = await Directory.systemTemp.createTemp('teampilot-cli-');
    addTearDown(() => tempDir.delete(recursive: true));

    final shimPath = '${tempDir.path}${Platform.pathSeparator}claude';
    await File(shimPath).writeAsString('#!/bin/sh\n');
    await File('$shimPath.cmd').writeAsString('@echo off\n');

    expect(
      CliToolLocator.resolveSpawnExecutable(shimPath),
      '$shimPath.cmd',
    );
  });

  test('resolveSpawnExecutable leaves bare PATH names unchanged', () {
    expect(CliToolLocator.resolveSpawnExecutable('claude'), 'claude');
  });

  test(
    'locate WSL path preserves the requested executable name on Windows',
    () async {
      if (!Platform.isWindows) return;
      final located = await const CliToolLocator('claude').locate(
        runner:
            (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
              if (executable == 'where') {
                return ProcessResult(1, 1, '', '');
              }
              expect(arguments, ['bash', '-ilc', 'command -v claude']);
              return ProcessResult(2, 0, '/usr/local/bin/claude\n', '');
            },
      );

      expect(located, 'wsl.exe /usr/local/bin/claude');
    },
  );
}
