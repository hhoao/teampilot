import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_one_shot_runner.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';

SSHRunResult _sshOk(String stdout, {int exitCode = 0}) {
  final bytes = utf8.encode(stdout);
  return SSHRunResult(
    output: bytes,
    stdout: bytes,
    stderr: Uint8List(0),
    exitCode: exitCode,
    exitSignal: null,
  );
}

void main() {
  group('LocalHostOneShotRunner', () {
    test('runs executable with argv', () async {
      final calls = <List<String>>[];
      final runner = LocalHostOneShotRunner(
        processRunner: (exe, args, {workingDirectory, environment, includeParentEnvironment = true, stdoutEncoding, stderrEncoding}) async {
          calls.add([exe, ...args]);
          return ProcessResult(0, 0, 'ok\n', '');
        },
      );

      final result = await runner.run(
        const HostRunRequest(executable: 'echo', arguments: ['hi']),
      );

      expect(result.succeeded, isTrue);
      expect(result.stdout, 'ok\n');
      expect(calls.single, ['echo', 'hi']);
    });
  });

  group('WslHostOneShotRunner', () {
    test('prefixes distro and forwards inner command', () async {
      final calls = <List<String>>[];
      final runner = WslHostOneShotRunner(
        distro: 'Ubuntu',
        processRunner: (exe, args, {workingDirectory, environment, includeParentEnvironment = true, stdoutEncoding, stderrEncoding}) async {
          calls.add([exe, ...args]);
          return ProcessResult(0, 0, '', '');
        },
      );

      await runner.run(
        HostRunRequest(
          executable: 'git',
          arguments: ['status'],
          workingDirectory: '/home/user/repo',
        ),
      );

      expect(
        calls.single,
        containsAll(['-d', 'Ubuntu', '--cd', '/home/user/repo', 'git', 'status']),
      );
    });
  });

  group('RemoteHostOneShotRunner', () {
    test('shell-quotes argv for execShell', () async {
      final commands = <String>[];
      final runner = RemoteHostOneShotRunner(
        execShell: (cmd) async {
          commands.add(cmd);
          return _sshOk('done\n');
        },
      );

      final result = await runner.run(
        HostRunRequest(
          executable: 'git',
          arguments: ['-C', '/repo/with spaces', 'status'],
        ),
      );

      expect(result.succeeded, isTrue);
      expect(commands.single, contains("'-C' '/repo/with spaces'"));
      expect(commands.single, endsWith("'status'"));
    });
  });

  group('hostOneShotRunnerForContext', () {
    test('picks local runner for native storage', () {
      AppStorage.installForTesting(
        filesystem: LocalFilesystem(),
        paths: AppPaths('/tmp/teampilot-test'),
        home: '/tmp',
        cwd: '/tmp',
      );
      addTearDown(AppStorage.resetForTesting);

      expect(
        hostOneShotRunnerForContext(AppStorage.context),
        isA<LocalHostOneShotRunner>(),
      );
    });
  });
}
