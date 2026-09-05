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

import '../../support/faithful_shell_exec.dart';

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
    configuredGitExecutable = null;
    GitService.debugResetExecutableCache();
    RemoteGitCommandRunner.debugResetAvailabilityCache();
  });

  group('RemoteGitCommandRunner', () {
    test('uses injected gitExecutable in run and probe', () async {
      final commands = <String>[];
      final runner = RemoteGitCommandRunner(
        gitExecutable: '/opt/git',
        execShell: (cmd) async {
          commands.add(cmd);
          return _sshOk('/opt/git\n');
        },
      );

      expect(await runner.isAvailable, isTrue);
      expect(commands.first, contains('/opt/git'));

      await runner.runInDirectory('/repo', ['status']);
      expect(commands.last, contains("'/opt/git'"));
    });

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

    test('isAvailable true when remote host has git (real shell semantics)', () async {
      // The probe must not swallow `command -v` output while still requiring
      // non-empty stdout as the success signal (SSH exit status can be null).
      final runner = RemoteGitCommandRunner(
        hostKey: 'probe-git-present',
        execShell: faithfulShellExec,
      );

      expect(await runner.isAvailable, isTrue);
    });

    test('isAvailable false when remote host lacks git', () async {
      final runner = RemoteGitCommandRunner(
        hostKey: 'probe-git-missing',
        execShell: (cmd) => faithfulShellExec(cmd, path: '/nonexistent'),
      );

      expect(await runner.isAvailable, isFalse);
    });

    test('isAvailable true for configured absolute executable (real shell semantics)', () async {
      final runner = RemoteGitCommandRunner(
        hostKey: 'probe-exe-absolute',
        gitExecutable: '/bin/sh',
        execShell: faithfulShellExec,
      );

      expect(await runner.isAvailable, isTrue);
    });

    test('isAvailable true for configured bare name on PATH (real shell semantics)', () async {
      final runner = RemoteGitCommandRunner(
        hostKey: 'probe-exe-bare',
        gitExecutable: 'sh',
        execShell: faithfulShellExec,
      );

      expect(await runner.isAvailable, isTrue);
    });

    test('isAvailable false for configured missing path (real shell semantics)', () async {
      final runner = RemoteGitCommandRunner(
        hostKey: 'probe-exe-missing',
        gitExecutable: '/nonexistent/git-x',
        execShell: faithfulShellExec,
      );

      expect(await runner.isAvailable, isFalse);
    });

    test('isAvailable false for configured non-executable path (real shell semantics)', () async {
      // `command -v` echoes non-executable paths, so the probe must gate
      // slash-paths on `test -x` instead.
      final runner = RemoteGitCommandRunner(
        hostKey: 'probe-exe-not-executable',
        gitExecutable: '/etc/hostname',
        execShell: faithfulShellExec,
      );

      expect(await runner.isAvailable, isFalse);
    });

    test('runInDirectory shell-quotes repo path and args', () async {
      final commands = <String>[];
      final runner = RemoteGitCommandRunner(
        execShell: (cmd) async {
          commands.add(cmd);
          return _sshOk('ok\n');
        },
      );

      final result = await runner.runInDirectory("/repo/with spaces", [
        'status',
        '--porcelain',
      ]);

      expect(result.exitCode, 0);
      expect(commands.single, contains("'--no-optional-locks'"));
      expect(commands.single, contains("'-C' '/repo/with spaces'"));
      expect(commands.single, endsWith("'status' '--porcelain'"));
    });
  });

  group('WslGitCommandRunner', () {
    test('isAvailable true when git exists in the distro (real shell semantics)', () async {
      // The probe must not swallow `command -v` output while still requiring
      // non-empty stdout as the success signal.
      final runner = WslGitCommandRunner(
        distro: 'Ubuntu',
        wslRunner: (exe, args, {stdoutEncoding, stderrEncoding}) async {
          final cmdIndex = args.indexOf('-lc');
          final cmd = cmdIndex >= 0 ? args[cmdIndex + 1] : '';
          return Process.run('sh', ['-c', cmd]);
        },
      );

      expect(await runner.isAvailable, isTrue);
    });

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
    test('uses injected gitExecutable', () async {
      final capturing = _CapturingHostRunner();
      final runner = LocalGitCommandRunner(
        gitExecutable: '/custom/git',
        runner:
            (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
              fail('locate must not run when gitExecutable is set');
            },
        hostRunner: capturing,
      );

      await runner.runInDirectory('/repo', ['status']);

      expect(capturing.seenExe, '/custom/git');
    });

    test('uses injected host runner for git execution', () async {
      var hostInvoked = false;
      final runner = LocalGitCommandRunner(
        runner:
            (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
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

    test('picks LocalGitCommandRunner when native', () {
      configuredGitExecutable = () => '/from/prefs/git';
      addTearDown(() => configuredGitExecutable = null);

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

class _CapturingHostRunner implements HostOneShotRunner {
  String? seenExe;

  @override
  Future<HostRunResult> run(HostRunRequest request) async {
    seenExe = request.executable;
    return const HostRunResult(exitCode: 0, stdout: 'ok\n', stderr: '');
  }
}
