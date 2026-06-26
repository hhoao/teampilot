import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/git/git_command_runner.dart';
import 'package:teampilot/services/git/git_service.dart';
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
  setUp(() {
    GitService.debugResetExecutableCache();
    RemoteGitCommandRunner.debugResetAvailabilityCache();
  });

  group('RemoteGitCommandRunner', () {
    test('isAvailable probes remote git on PATH', () async {
      final commands = <String>[];
      final runner = RemoteGitCommandRunner(
        execShell: (cmd) async {
          commands.add(cmd);
          return _sshOk('/usr/bin/git\n');
        },
      );

      expect(await runner.isAvailable, isTrue);
      expect(commands.single, contains('command -v git'));
    });

    test('runInDirectory shell-quotes repo path and args', () async {
      final commands = <String>[];
      final runner = RemoteGitCommandRunner(
        execShell: (cmd) async {
          commands.add(cmd);
          return _sshOk('ok\n');
        },
      );

      final result = await runner.runInDirectory(
        "/repo/with spaces",
        ['status', '--porcelain'],
      );

      expect(result.exitCode, 0);
      expect(commands.single, contains("'--no-optional-locks'"));
      expect(commands.single, contains("'-C' '/repo/with spaces'"));
      expect(commands.single, endsWith("'status' '--porcelain'"));
    });
  });

  group('WslGitCommandRunner', () {
    test('runInDirectory invokes wsl.exe git -C', () async {
      final calls = <List<String>>[];
      final runner = WslGitCommandRunner(
        distro: 'Ubuntu',
        wslRunner: (exe, args, {stdoutEncoding, stderrEncoding}) async {
          calls.add(args);
          return ProcessResult(0, 0, 'ok\n', '');
        },
      );

      final result = await runner.runInDirectory('/home/user/repo', [
        'rev-parse',
        '--is-inside-work-tree',
      ]);

      expect(result.exitCode, 0);
      expect(calls.single, containsAll(['-d', 'Ubuntu', 'git', '-C']));
      expect(calls.single, contains('/home/user/repo'));
    });
  });

  group('LocalGitCommandRunner', () {
    test('uses injected host runner for git execution', () async {
      var hostInvoked = false;
      final runner = LocalGitCommandRunner(
        runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
          return ProcessResult(0, 0, '/usr/bin/git\n', '');
        },
        hostRunner: _RecordingHostRunner(() => hostInvoked = true),
      );

      final result = await runner.runInDirectory('/repo', ['status']);

      expect(hostInvoked, isTrue);
      expect(result.exitCode, 0);
    });
  });

  group('gitCommandRunnerForContext', () {
    test('picks local runner for native storage', () {
      AppStorage.installForTesting(
        filesystem: LocalFilesystem(),
        paths: AppPaths('/tmp/teampilot-test'),
        home: '/tmp',
        cwd: '/tmp',
      );
      addTearDown(AppStorage.resetForTesting);

      expect(
        gitCommandRunnerForContext(AppStorage.context),
        isA<LocalGitCommandRunner>(),
      );
    });
  });
}

class _RecordingHostRunner implements HostOneShotRunner {
  _RecordingHostRunner(this._onRun);

  final void Function() _onRun;

  @override
  Future<HostRunResult> run(HostRunRequest request) async {
    _onRun();
    return const HostRunResult(exitCode: 0, stdout: 'ok\n', stderr: '');
  }
}
