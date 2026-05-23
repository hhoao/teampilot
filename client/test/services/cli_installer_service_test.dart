import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli_installer_service.dart';

void main() {
  test('installs Claude Code locally with npm and resolves the executable', () async {
    final commands = <String>[];
    final installer = CliInstallerService(
      isWindowsOverride: false,
      localRunner: (command) async {
        commands.add(command.commandLine);
        if (command.commandLine == 'command -v npm') {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '/usr/bin/npm\n',
          );
        }
        if (command.commandLine == 'npm install -g @anthropic-ai/claude-code') {
          return const CliInstallerCommandResult(exitCode: 0);
        }
        if (command.commandLine == 'which claude') {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '/usr/local/bin/claude\n',
          );
        }
        return const CliInstallerCommandResult(exitCode: 127);
      },
    );

    final result = await installer.install(
      cli: TeamCli.claude,
      mode: CliInstallMode.local,
    );

    expect(result.success, isTrue);
    expect(result.executablePath, '/usr/local/bin/claude');
    expect(commands, [
      'command -v npm',
      'npm install -g @anthropic-ai/claude-code',
      'which claude',
    ]);
  });

  test('installs Claude Code locally on Windows using where', () async {
    final commands = <String>[];
    final installer = CliInstallerService(
      isWindowsOverride: true,
      localRunner: (command) async {
        commands.add(command.commandLine);
        if (command.commandLine == 'where npm') {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: r'C:\Program Files\nodejs\npm.cmd',
          );
        }
        if (command.commandLine == 'npm install -g @anthropic-ai/claude-code') {
          return const CliInstallerCommandResult(exitCode: 0);
        }
        if (command.commandLine == 'where claude') {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: r'C:\Users\alice\AppData\Roaming\npm\claude.cmd',
          );
        }
        return const CliInstallerCommandResult(exitCode: 127);
      },
    );

    final result = await installer.install(
      cli: TeamCli.claude,
      mode: CliInstallMode.local,
    );

    expect(result.success, isTrue);
    expect(result.executablePath, r'C:\Users\alice\AppData\Roaming\npm\claude.cmd');
    expect(commands, [
      'where npm',
      'npm install -g @anthropic-ai/claude-code',
      'where claude',
    ]);
  });

  test('falls back to WSL on Windows when where claude misses', () async {
    final commands = <String>[];
    final installer = CliInstallerService(
      isWindowsOverride: true,
      localRunner: (command) async {
        commands.add(command.commandLine);
        if (command.commandLine == 'where npm') {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: r'C:\Program Files\nodejs\npm.cmd',
          );
        }
        if (command.commandLine == 'npm install -g @anthropic-ai/claude-code') {
          return const CliInstallerCommandResult(exitCode: 0);
        }
        if (command.commandLine == 'where claude') {
          return const CliInstallerCommandResult(exitCode: 1);
        }
        if (command.commandLine == "wsl.exe bash -ilc 'command -v claude'") {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '/home/alice/.npm-global/bin/claude\n',
          );
        }
        return const CliInstallerCommandResult(exitCode: 127);
      },
    );

    final result = await installer.install(
      cli: TeamCli.claude,
      mode: CliInstallMode.local,
    );

    expect(result.success, isTrue);
    expect(result.executablePath, 'wsl.exe /home/alice/.npm-global/bin/claude');
    expect(commands, [
      'where npm',
      'npm install -g @anthropic-ai/claude-code',
      'where claude',
      "wsl.exe bash -ilc 'command -v claude'",
    ]);
  });

  test('bootstraps local Node when npm is missing on Unix', () async {
    final commands = <String>[];
    final installer = CliInstallerService(
      isWindowsOverride: false,
      localRunner: (command) async {
        commands.add(command.commandLine);
        if (command.commandLine == 'command -v npm') {
          return const CliInstallerCommandResult(exitCode: 1);
        }
        if (command.commandLine.contains('nodejs.org/dist/')) {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '10.9.0\n',
          );
        }
        if (command.commandLine.contains(
          r"$HOME/.local/share/teampilot/node/v24.15.0/bin/npm install -g @anthropic-ai/claude-code",
        )) {
          return const CliInstallerCommandResult(exitCode: 0);
        }
        if (command.commandLine == 'which claude') {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '/home/alice/.local/bin/claude\n',
          );
        }
        return const CliInstallerCommandResult(exitCode: 127);
      },
    );

    final result = await installer.install(
      cli: TeamCli.claude,
      mode: CliInstallMode.local,
    );

    expect(result.success, isTrue);
    expect(result.executablePath, '/home/alice/.local/bin/claude');
    expect(commands[0], 'command -v npm');
    expect(commands[1], contains('nodejs.org/dist/'));
    expect(commands[2], contains('npm install -g @anthropic-ai/claude-code'));
  });

  test('reports local npm install failure', () async {
    final installer = CliInstallerService(
      isWindowsOverride: false,
      localRunner: (command) async {
        if (command.commandLine == 'command -v npm') {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '/usr/bin/npm\n',
          );
        }
        return const CliInstallerCommandResult(
          exitCode: 1,
          stderr: 'permission denied',
        );
      },
    );

    final result = await installer.install(
      cli: TeamCli.claude,
      mode: CliInstallMode.local,
    );

    expect(result.success, isFalse);
    expect(result.message, contains('permission denied'));
  });

  test('installs Claude Code on SSH host when remote npm exists', () async {
    final commands = <String>[];
    final installer = CliInstallerService(
      sshRunner: (profile, command) async {
        commands.add(command.commandLine);
        if (command.commandLine == 'command -v npm') {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '/usr/bin/npm\n',
          );
        }
        if (command.commandLine == 'npm install -g @anthropic-ai/claude-code') {
          return const CliInstallerCommandResult(exitCode: 0);
        }
        if (command.commandLine == 'command -v claude') {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '/home/alice/.npm-global/bin/claude\n',
          );
        }
        return const CliInstallerCommandResult(exitCode: 127);
      },
    );

    final result = await installer.install(
      cli: TeamCli.claude,
      mode: CliInstallMode.ssh,
      sshProfile: _profile,
    );

    expect(result.success, isTrue);
    expect(result.executablePath, '/home/alice/.npm-global/bin/claude');
    expect(commands, [
      'command -v npm',
      'npm install -g @anthropic-ai/claude-code',
      'command -v claude',
    ]);
  });

  test('bootstraps Node npm on SSH host when npm is missing', () async {
    final commands = <String>[];
    final installer = CliInstallerService(
      sshRunner: (profile, command) async {
        commands.add(command.commandLine);
        if (command.commandLine == 'command -v npm') {
          return const CliInstallerCommandResult(exitCode: 1);
        }
        if (command.commandLine.contains('nodejs.org/dist/')) {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout:
                '/home/alice/.local/share/teampilot/node/v24.15.0/bin/npm\n',
          );
        }
        if (command.commandLine ==
            r'$HOME/.local/share/teampilot/node/v24.15.0/bin/npm install -g @anthropic-ai/claude-code') {
          return const CliInstallerCommandResult(exitCode: 0);
        }
        if (command.commandLine == 'command -v claude') {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '/home/alice/.local/bin/claude\n',
          );
        }
        return const CliInstallerCommandResult(exitCode: 127);
      },
    );

    final result = await installer.install(
      cli: TeamCli.claude,
      mode: CliInstallMode.ssh,
      sshProfile: _profile,
    );

    expect(result.success, isTrue);
    expect(result.executablePath, '/home/alice/.local/bin/claude');
    expect(commands[0], 'command -v npm');
    expect(commands[1], contains('nodejs.org/dist/'));
    expect(commands[2], contains('npm install -g @anthropic-ai/claude-code'));
  });

  test('requires an SSH profile for SSH install', () async {
    final installer = CliInstallerService(
      sshRunner: (_, _) async => const CliInstallerCommandResult(exitCode: 0),
    );

    final result = await installer.install(
      cli: TeamCli.claude,
      mode: CliInstallMode.ssh,
    );

    expect(result.success, isFalse);
    expect(result.message, contains('SSH'));
  });
}

const _profile = SshProfile(
  id: 'ssh-1',
  name: 'dev',
  host: 'example.com',
  username: 'alice',
);
