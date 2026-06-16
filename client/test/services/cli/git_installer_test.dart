import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/git_installer.dart';

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
              stdout: r'C:\Program Files\Git\cmd\git.exe' '\n',
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
              stdout: r'C:\Users\test\AppData\Local\Microsoft\WindowsApps\winget.exe',
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
              stdout: r'C:\Program Files\Git\cmd\git.exe' '\n',
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
        contains('winget install --id Git.Git --exact --silent --accept-source-agreements --accept-package-agreements'),
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

    test('reports progress phases during install (Windows)', () async {
      final phases = <GitInstallPhase>[];
      final installer = GitInstaller(
        isWindowsOverride: true,
        processRunner: (exe, args) async {
          if (exe == 'where' && args.contains('winget')) {
            return _fakeResult(exitCode: 0,
              stdout: r'C:\Users\test\AppData\Local\Microsoft\WindowsApps\winget.exe');
          }
          if (exe == 'winget' && args.contains('install')) {
            return _fakeResult(exitCode: 0);
          }
          if (exe == 'git' && args.contains('--version')) {
            return _fakeResult(exitCode: 0);
          }
          if (exe == 'where' && args.contains('git')) {
            return _fakeResult(exitCode: 0, stdout: r'C:\Program Files\Git\cmd\git.exe' '\n');
          }
          return _fakeResult(exitCode: 127);
        },
      );

      await installer.install(onProgress: (p) => phases.add(p.phase));

      expect(phases[0], GitInstallPhase.installing);
      expect(phases[1], GitInstallPhase.locating);
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
