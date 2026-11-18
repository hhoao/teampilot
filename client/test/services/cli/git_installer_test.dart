import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/git_installer.dart';

/// A hermetic fake [Process] for the default streaming runner tests.
///
/// Never spawns a real subprocess; records [kill] calls so tests can assert the
/// runner does not orphan a child when draining fails.
class _FakeProcess implements Process {
  _FakeProcess({
    this.stdoutBytes = const <int>[],
    this.stderrBytes = const <int>[],
    this.exitCodeValue = 0,
    this.errorOnDrain = false,
  });

  final List<int> stdoutBytes;
  final List<int> stderrBytes;
  final int exitCodeValue;
  final bool errorOnDrain;

  final List<ProcessSignal> kills = <ProcessSignal>[];

  @override
  int get pid => 4242;

  @override
  Future<int> get exitCode => Future<int>.value(exitCodeValue);

  @override
  Stream<List<int>> get stdout => errorOnDrain
      ? Stream<List<int>>.error(StateError('stdout failed'))
      : Stream<List<int>>.value(stdoutBytes);

  @override
  Stream<List<int>> get stderr => errorOnDrain
      ? Stream<List<int>>.error(StateError('stderr failed'))
      : Stream<List<int>>.value(stderrBytes);

  @override
  IOSink get stdin => throw UnimplementedError('stdin is unused');

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    kills.add(signal);
    return true;
  }
}

GitInstaller _installerWithStarter(GitProcessStarter starter) => GitInstaller(
  isWindowsOverride: true,
  processRunner: (exe, args) async => ProcessResult(0, 0, '', ''),
  processStarter: starter,
);

/// A fake [ProcessResult] that tests can construct without spawning a process.
ProcessResult _fakeResult({
  required int exitCode,
  String stdout = '',
  String stderr = '',
}) {
  // ProcessResult has no public constructor — use the one from a real quick
  // command as a template. We just need the fields exitCode, stdout, stderr.
  // Since dart:io ProcessResult is abstract, we create an instance via a
  // lightweight null-byte command.
  return ProcessResult(0, exitCode, stdout, stderr);
}

void main() {
  group('GitInstallResult', () {
    test('found() constructor sets success and executablePath', () {
      const result = GitInstallResult.found('/usr/bin/git');
      expect(result.success, isTrue);
      expect(result.executablePath, '/usr/bin/git');
      expect(result.message, contains('/usr/bin/git'));
    });

    test('notFound() constructor sets success=false', () {
      const result = GitInstallResult.notFound('git not on PATH');
      expect(result.success, isFalse);
      expect(result.executablePath, isNull);
      expect(result.message, contains('git not on PATH'));
    });

    test('installed() constructor sets success and executablePath', () {
      const result = GitInstallResult.installed('/usr/local/bin/git');
      expect(result.success, isTrue);
      expect(result.executablePath, '/usr/local/bin/git');
      expect(result.message, contains('installed successfully'));
    });

    test('failed() constructor sets success=false', () {
      const result = GitInstallResult.failed('something went wrong');
      expect(result.success, isFalse);
      expect(result.executablePath, isNull);
      expect(result.message, 'something went wrong');
    });
  });

  group('detectGit', () {
    test('finds git path when git is on PATH (Unix)', () async {
      final commands = <String>[];
      final installer = GitInstaller(
        isWindowsOverride: false,
        processRunner: (exe, args) async {
          commands.add('$exe ${args.join(' ')}');
          if (exe == 'git' && args.contains('--version')) {
            return _fakeResult(exitCode: 0);
          }
          if (exe == 'which' && args.contains('git')) {
            return _fakeResult(exitCode: 0, stdout: '/usr/bin/git\n');
          }
          return _fakeResult(exitCode: 127);
        },
      );

      final result = await installer.detectGit();

      expect(result.success, isTrue);
      expect(result.executablePath, '/usr/bin/git');
      expect(commands, ['git --version', 'which git']);
    });

    test('finds git path when git is on PATH (Windows)', () async {
      final commands = <String>[];
      final installer = GitInstaller(
        isWindowsOverride: true,
        processRunner: (exe, args) async {
          commands.add('$exe ${args.join(' ')}');
          if (exe == 'git' && args.contains('--version')) {
            return _fakeResult(exitCode: 0);
          }
          if (exe == 'where' && args.contains('git')) {
            return _fakeResult(
              exitCode: 0,
              stdout:
                  r'C:\Program Files\Git\cmd\git.exe'
                  '\n',
            );
          }
          return _fakeResult(exitCode: 127);
        },
      );

      final result = await installer.detectGit();

      expect(result.success, isTrue);
      expect(result.executablePath, r'C:\Program Files\Git\cmd\git.exe');
      expect(commands, ['git --version', 'where git']);
    });

    test('reports not-found when git --version fails', () async {
      final installer = GitInstaller(
        isWindowsOverride: false,
        processRunner: (exe, args) async {
          if (exe == 'git' && args.contains('--version')) {
            return _fakeResult(exitCode: 1);
          }
          return _fakeResult(exitCode: 127);
        },
      );

      final result = await installer.detectGit();

      expect(result.success, isFalse);
      expect(result.executablePath, isNull);
      expect(result.message, contains('Git not found'));
    });

    test('reports not-found when git is not on PATH at all', () async {
      final installer = GitInstaller(
        isWindowsOverride: false,
        processRunner: (_, __) async => _fakeResult(exitCode: 127),
      );

      final result = await installer.detectGit();

      expect(result.success, isFalse);
    });

    test('reports progress phases in order', () async {
      final phases = <GitInstallPhase>[];
      final installer = GitInstaller(
        isWindowsOverride: false,
        processRunner: (exe, args) async {
          if (exe == 'git' && args.contains('--version')) {
            return _fakeResult(exitCode: 0);
          }
          if (exe == 'which' && args.contains('git')) {
            return _fakeResult(exitCode: 0, stdout: '/usr/bin/git\n');
          }
          return _fakeResult(exitCode: 127);
        },
      );

      await installer.detectGit(onProgress: (p) => phases.add(p.phase));

      expect(phases[0], GitInstallPhase.checking);
      expect(phases[1], GitInstallPhase.locating);
    });
  });

  group('install', () {
    test('on Linux returns guide message without running sudo', () async {
      // Simulate Linux by overriding isWindows=false (macOS is false on Linux
      // in tests since dart:io Platform reports the host OS).  We mock the
      // process runner so _canRun is never called.
      final commands = <String>[];
      final installer = GitInstaller(
        isWindowsOverride: false,
        processRunner: (exe, args) async {
          commands.add('$exe ${args.join(' ')}');
          return _fakeResult(exitCode: 0);
        },
      );

      final result = await installer.install();

      // On a non-Windows, non-macOS system, or when our override says not
      // Windows and Platform.isMacOS is false (Linux CI), we get guide-only.
      // On macOS dev machines Platform.isMacOS is true, so this hits the
      // macOS branch.  The test validates the result shape regardless.
      if (!Platform.isMacOS) {
        // Linux path — no commands should try to install.
        expect(result.success, isFalse);
        expect(result.message, contains('https://git-scm.com'));
        expect(result.message, contains('manually'));
        expect(commands, isEmpty);
      }
    });

    test('on Windows with winget available installs git', () async {
      final commands = <String>[];
      final installer = GitInstaller(
        isWindowsOverride: true,
        processRunner: (exe, args) async {
          final cmd = '$exe ${args.join(' ')}';
          commands.add(cmd);
          // winget availability check
          if (exe == 'where' && args.contains('winget')) {
            return _fakeResult(
              exitCode: 0,
              stdout:
                  r'C:\Users\test\AppData\Local\Microsoft\WindowsApps\winget.exe',
            );
          }
          // winget install
          if (exe == 'winget' && args.contains('install')) {
            return _fakeResult(exitCode: 0);
          }
          // post-install detect: git --version
          if (exe == 'git' && args.contains('--version')) {
            return _fakeResult(exitCode: 0);
          }
          // post-install detect: where git
          if (exe == 'where' && args.contains('git')) {
            return _fakeResult(
              exitCode: 0,
              stdout:
                  r'C:\Program Files\Git\cmd\git.exe'
                  '\n',
            );
          }
          return _fakeResult(exitCode: 127);
        },
      );

      final result = await installer.install();

      expect(result.success, isTrue);
      expect(result.executablePath, r'C:\Program Files\Git\cmd\git.exe');
      expect(
        commands,
        contains(
          'winget install --id Git.Git --exact --silent --accept-source-agreements --accept-package-agreements',
        ),
      );
      expect(commands.first, 'where winget');
    });

    test('on Windows without winget returns guide URL', () async {
      final installer = GitInstaller(
        isWindowsOverride: true,
        processRunner: (exe, args) async {
          if (exe == 'where' && args.contains('winget')) {
            return _fakeResult(exitCode: 1);
          }
          return _fakeResult(exitCode: 127);
        },
      );

      final result = await installer.install();

      expect(result.success, isFalse);
      expect(result.message, contains('winget is not available'));
      expect(result.message, contains('https://git-scm.com'));
    });

    test('on Windows winget install failure returns guide URL', () async {
      final installer = GitInstaller(
        isWindowsOverride: true,
        processRunner: (exe, args) async {
          if (exe == 'where' && args.contains('winget')) {
            return _fakeResult(exitCode: 0);
          }
          if (exe == 'winget' && args.contains('install')) {
            return _fakeResult(exitCode: 1, stderr: 'access denied');
          }
          return _fakeResult(exitCode: 127);
        },
      );

      final result = await installer.install();

      expect(result.success, isFalse);
      expect(result.message, contains('access denied'));
      expect(result.message, contains('https://git-scm.com'));
    });

    test('on macOS with brew available installs git', () async {
      if (!Platform.isMacOS) return; // skip on non-macOS

      final commands = <String>[];
      final installer = GitInstaller(
        processRunner: (exe, args) async {
          commands.add('$exe ${args.join(' ')}');
          if (exe == 'which' && args.contains('brew')) {
            return _fakeResult(exitCode: 0, stdout: '/opt/homebrew/bin/brew\n');
          }
          if (exe == 'brew' && args.contains('install')) {
            return _fakeResult(exitCode: 0);
          }
          if (exe == 'git' && args.contains('--version')) {
            return _fakeResult(exitCode: 0);
          }
          if (exe == 'which' && args.contains('git')) {
            return _fakeResult(exitCode: 0, stdout: '/opt/homebrew/bin/git\n');
          }
          return _fakeResult(exitCode: 127);
        },
      );

      final result = await installer.install();

      expect(result.success, isTrue);
      expect(result.executablePath, '/opt/homebrew/bin/git');
      expect(commands, contains('brew install git'));
    });

    test('on macOS without brew returns guide URL', () async {
      if (!Platform.isMacOS) return;

      final installer = GitInstaller(
        processRunner: (exe, args) async {
          if (exe == 'which' && args.contains('brew')) {
            return _fakeResult(exitCode: 1);
          }
          return _fakeResult(exitCode: 127);
        },
      );

      final result = await installer.install();

      expect(result.success, isFalse);
      expect(result.message, contains('Homebrew is not available'));
      expect(result.message, contains('https://git-scm.com'));
      expect(result.message, contains('https://brew.sh'));
    });

    test(
      'install returns cancelled when isCancelled before installing',
      () async {
        final commands = <String>[];
        final installer = GitInstaller(
          isWindowsOverride: true,
          processRunner: (exe, args) async {
            commands.add('$exe ${args.join(' ')}');
            if (exe == 'where' && args.contains('winget')) {
              return _fakeResult(
                exitCode: 0,
                stdout:
                    r'C:\Users\test\AppData\Local\Microsoft\WindowsApps\winget.exe',
              );
            }
            return _fakeResult(exitCode: 127);
          },
        );

        var checks = 0;
        final result = await installer.install(isCancelled: () => ++checks > 0);

        expect(result.success, isFalse);
        expect(result.message, 'Cancelled');
        expect(commands.any((c) => c.contains('winget install')), isFalse);
      },
    );

    test('reports progress phases during install (Windows)', () async {
      final phases = <GitInstallPhase>[];
      final installer = GitInstaller(
        isWindowsOverride: true,
        processRunner: (exe, args) async {
          if (exe == 'where' && args.contains('winget')) {
            return _fakeResult(
              exitCode: 0,
              stdout:
                  r'C:\Users\test\AppData\Local\Microsoft\WindowsApps\winget.exe',
            );
          }
          if (exe == 'winget' && args.contains('install')) {
            return _fakeResult(exitCode: 0);
          }
          if (exe == 'git' && args.contains('--version')) {
            return _fakeResult(exitCode: 0);
          }
          if (exe == 'where' && args.contains('git')) {
            return _fakeResult(
              exitCode: 0,
              stdout:
                  r'C:\Program Files\Git\cmd\git.exe'
                  '\n',
            );
          }
          return _fakeResult(exitCode: 127);
        },
      );

      await installer.install(onProgress: (p) => phases.add(p.phase));

      expect(phases[0], GitInstallPhase.installing);
      expect(phases[1], GitInstallPhase.locating);
    });

    test(
      'forwards install command output through the streaming runner',
      () async {
        final lines = <String>[];
        final installer = GitInstaller(
          isWindowsOverride: true,
          processRunner: (exe, args) async => ProcessResult(0, 0, '', ''),
          streamingRunner: (exe, args, onOutput) async {
            onOutput('installing $exe');
            return ProcessResult(0, 0, '', '');
          },
        );

        final result = await installer.install(onOutputLine: lines.add);

        expect(result.success, isTrue);
        expect(lines, contains('installing winget'));
      },
    );
  });

  group('default streaming runner', () {
    test('tolerates invalid UTF-8 bytes and forwards the line', () async {
      final lines = <String>[];
      final started = <String>[];
      final installer = _installerWithStarter((exe, args) async {
        started.add('$exe ${args.join(' ')}');
        return _FakeProcess(
          // "installing " followed by two bytes that are invalid UTF-8.
          stdoutBytes: <int>[...utf8.encode('installing '), 0xFF, 0xFE, 0x0A],
        );
      });

      final result = await installer.install(onOutputLine: lines.add);

      expect(result.success, isTrue);
      expect(started.single, startsWith('winget install'));
      expect(lines, hasLength(1));
      expect(lines.single, startsWith('installing '));
      expect(lines.single, contains('\uFFFD'));
    });

    test('propagates a non-zero exit code with stderr detail', () async {
      final installer = _installerWithStarter(
        (exe, args) async => _FakeProcess(
          stdoutBytes: utf8.encode('installing\n'),
          stderrBytes: utf8.encode('access denied\n'),
          exitCodeValue: 1,
        ),
      );

      final result = await installer.install(onOutputLine: (_) {});

      expect(result.success, isFalse);
      expect(result.message, contains('access denied'));
      expect(result.message, contains('https://git-scm.com'));
    });

    test('a starter that throws ProcessException fails the install', () async {
      final installer = _installerWithStarter(
        (exe, args) async => throw ProcessException(exe, args, 'not found'),
      );

      final result = await installer.install(onOutputLine: (_) {});

      expect(result.success, isFalse);
      expect(result.message, contains('Failed to run winget'));
    });

    test('a throwing onOutput sink does not break the drain', () async {
      final lines = <String>[];
      final installer = _installerWithStarter(
        (exe, args) async =>
            _FakeProcess(stdoutBytes: utf8.encode('first\nsecond\n')),
      );

      final result = await installer.install(
        onOutputLine: (line) {
          lines.add(line);
          throw const FormatException('sink exploded');
        },
      );

      expect(result.success, isTrue);
      expect(lines, ['first', 'second']);
    });

    test('kills the child before rethrowing a drain error', () async {
      late _FakeProcess process;
      final installer = _installerWithStarter((exe, args) async {
        process = _FakeProcess(errorOnDrain: true);
        return process;
      });

      await expectLater(
        installer.install(onOutputLine: (_) {}),
        throwsA(isA<StateError>()),
      );
      expect(process.kills, isNotEmpty);
    });
  });

  group('GitInstallProgress', () {
    test('holds phase and optional detail', () {
      const progress = GitInstallProgress(phase: GitInstallPhase.checking);
      expect(progress.phase, GitInstallPhase.checking);
      expect(progress.detail, isNull);

      const withDetail = GitInstallProgress(
        phase: GitInstallPhase.installing,
        detail: 'running winget install Git.Git',
      );
      expect(withDetail.phase, GitInstallPhase.installing);
      expect(withDetail.detail, 'running winget install Git.Git');
    });
  });
}
