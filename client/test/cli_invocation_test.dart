import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli_invocation.dart';
import 'package:teampilot/services/launch_command_builder.dart';

void main() {
  test('splits a wsl command into executable and prefix args', () {
    final invocation = CliInvocation.fromExecutable(
      'wsl.exe /usr/local/bin/flashskyai',
    );

    expect(invocation.executable, 'wsl.exe');
    expect(invocation.prefixArgs, ['/usr/local/bin/flashskyai']);
    expect(invocation.withArgs(['--team', 'agent']), [
      '/usr/local/bin/flashskyai',
      '--team',
      'agent',
    ]);
    if (invocation.usesWsl) {
      expect(
        invocation.withArgs(
          ['--team', 'agent'],
          environment: const {'LLM_CONFIG_PATH': '/mnt/c/config.json'},
        ),
        [
          'env',
          'LLM_CONFIG_PATH=/mnt/c/config.json',
          '/usr/local/bin/flashskyai',
          '--team',
          'agent',
        ],
      );
    }
  });

  test('converts drive-letter paths for wsl cli calls', () {
    expect(
      LaunchCommandBuilder.windowsPathToWsl(r'C:\Users\hhoa\git\agent'),
      '/mnt/c/Users/hhoa/git/agent',
    );
    expect(LaunchCommandBuilder.windowsPathToWsl(r'D:\'), '/mnt/d');
    expect(
      LaunchCommandBuilder.windowsPathToWsl(
        r'\\wsl.localhost\Ubuntu\home\hhoa\project',
      ),
      '/home/hhoa/project',
    );
    expect(
      LaunchCommandBuilder.windowsPathToWsl(
        r'\wsl.localhost\Ubuntu\home\hhoa\project',
      ),
      '/home/hhoa/project',
    );
  });

  test('treats WSL UNC executable paths as wsl invocations on Windows', () {
    final invocation = CliInvocation.fromExecutable(
      r'\\wsl.localhost\Ubuntu\home\hhoa\flashskyai\dist\flashskyai',
    );

    if (invocation.usesWsl) {
      expect(invocation.executable, 'wsl.exe');
      expect(invocation.prefixArgs, ['/home/hhoa/flashskyai/dist/flashskyai']);
    }
  });

  test(
    'treats single-slash WSL executable paths as wsl invocations on Windows',
    () {
      final invocation = CliInvocation.fromExecutable(
        r'\wsl.localhost\Ubuntu\home\hhoa\flashskai-ubuntu-wsl\dist\flashskyai',
      );

      if (invocation.usesWsl) {
        expect(invocation.executable, 'wsl.exe');
        expect(invocation.prefixArgs, [
          '/home/hhoa/flashskai-ubuntu-wsl/dist/flashskyai',
        ]);
      }
    },
  );

  test('keeps backslashes in quoted Windows executable paths', () {
    final invocation = CliInvocation.fromExecutable(
      r'"C:\Program Files\FlashskyAI\flashskyai.exe"',
    );

    expect(
      invocation.executable,
      r'C:\Program Files\FlashskyAI\flashskyai.exe',
    );
    expect(invocation.prefixArgs, isEmpty);
  });

  test('keeps explicit wsl distribution options unchanged', () {
    final invocation = CliInvocation.fromExecutable(
      'wsl.exe -d Ubuntu flashskyai',
    );

    if (invocation.usesWsl) {
      expect(invocation.prefixArgs, ['-d', 'Ubuntu', 'flashskyai']);
    }
  });

  test(
    'buildArguments converts working directories when wsl mode is enabled',
    () {
      expect(
        LaunchCommandBuilder.buildSessionPrefixArgs(
          workingDirectory: r'C:\Users\hhoa\git\agent',
          additionalDirectories: const [r'D:\data'],
          useWslPaths: true,
        ),
        ['--dir', '/mnt/c/Users/hhoa/git/agent', '--add-dir', '/mnt/d/data'],
      );
    },
  );
}
