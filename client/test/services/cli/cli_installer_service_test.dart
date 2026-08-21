import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_installer_service.dart';

bool _isClaudeNpmInstall(String line) =>
    line.contains('npm install -g --prefix') &&
    line.contains('@anthropic-ai/claude-code');

bool _isRemoteClaudeLocate(String line) =>
    line.startsWith('sh -c') && line.contains('command -v claude');

bool _isNpmVersionProbe(String line) =>
    line.startsWith('sh -c') &&
    line.contains('--version') &&
    !line.contains('is_termux=0');

bool _isTermuxProbe(String line) =>
    line.startsWith('sh -c') &&
    line.contains('is_termux=0') &&
    line.contains('TERMUX=1') &&
    line.contains('TERMUX=0');

bool _isGlibcProbe(String line) =>
    line.startsWith('sh -c') &&
    line.contains('ldd --version') &&
    line.contains('GLIBC=');

bool _isPrefixAwareNpmLocate(String line) =>
    line.startsWith('sh -c') &&
    line.contains('export PATH=') &&
    line.contains('command -v npm') &&
    !line.contains('nodejs.org/dist/');

CliInstallerCommandResult _termuxProbeNotTermux() =>
    const CliInstallerCommandResult(exitCode: 0, stdout: 'TERMUX=0\n');

void main() {
  test('preferred node path supplies sibling npm before PATH probe', () async {
    final commands = <String>[];
    final installer = CliInstallerService(
      isWindowsOverride: false,
      preferredNodePath: () => '/opt/node/bin/node',
      localRunner: (command) async {
        commands.add(command.commandLine);
        if (command.commandLine == 'which /opt/node/bin/npm') {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '/opt/node/bin/npm\n',
          );
        }
        if (command.commandLine == 'which npm') {
          return const CliInstallerCommandResult(exitCode: 1);
        }
        if (_isClaudeNpmInstall(command.commandLine) &&
            command.commandLine.contains('/opt/node/bin/npm')) {
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
      cli: CliTool.claude,
      mode: CliInstallMode.local,
    );

    expect(result.success, isTrue);
    expect(result.executablePath, '/usr/local/bin/claude');
    expect(commands.length, 3);
    expect(commands[0], 'which /opt/node/bin/npm');
    expect(_isClaudeNpmInstall(commands[1]), isTrue);
    expect(commands[1], contains('/opt/node/bin/npm'));
    expect(commands[2], 'which claude');
    expect(commands.any((line) => line == 'which npm'), isFalse);
  });

  test('falls back to PATH npm when preferred node unset', () async {
    final commands = <String>[];
    final installer = CliInstallerService(
      isWindowsOverride: false,
      preferredNodePath: null,
      localRunner: (command) async {
        commands.add(command.commandLine);
        if (command.commandLine == 'which npm') {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '/usr/bin/npm\n',
          );
        }
        if (_isClaudeNpmInstall(command.commandLine) &&
            command.commandLine.contains('/usr/bin/npm')) {
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
      cli: CliTool.claude,
      mode: CliInstallMode.local,
    );

    expect(result.success, isTrue);
    expect(result.executablePath, '/usr/local/bin/claude');
    expect(commands[0], 'which npm');
    expect(_isClaudeNpmInstall(commands[1]), isTrue);
    expect(commands[2], 'which claude');
  });

  test(
    'installs Claude Code locally with npm and resolves the executable',
    () async {
      final commands = <String>[];
      final installer = CliInstallerService(
        isWindowsOverride: false,
        localRunner: (command) async {
          commands.add(command.commandLine);
          if (command.commandLine == 'which npm') {
            return const CliInstallerCommandResult(
              exitCode: 0,
              stdout: '/usr/bin/npm\n',
            );
          }
          if (_isClaudeNpmInstall(command.commandLine) &&
              command.commandLine.contains('/usr/bin/npm')) {
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
        cli: CliTool.claude,
        mode: CliInstallMode.local,
      );

      expect(result.success, isTrue);
      expect(result.executablePath, '/usr/local/bin/claude');
      expect(commands.length, 3);
      expect(commands[0], 'which npm');
      expect(_isClaudeNpmInstall(commands[1]), isTrue);
      expect(commands[2], 'which claude');
    },
  );

  test('install returns early when cancelled before installingCli', () async {
    var npmInstallRuns = 0;
    final installer = CliInstallerService(
      isWindowsOverride: false,
      localRunner: (command) async {
        if (_isClaudeNpmInstall(command.commandLine)) {
          npmInstallRuns++;
        }
        if (command.commandLine == 'which npm') {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '/usr/bin/npm\n',
          );
        }
        return const CliInstallerCommandResult(exitCode: 127);
      },
    );

    var checks = 0;
    final result = await installer.install(
      cli: CliTool.claude,
      mode: CliInstallMode.local,
      isCancelled: () => ++checks > 1,
    );

    expect(result.success, isFalse);
    expect(result.message, 'Cancelled');
    expect(npmInstallRuns, 0);
  });

  test('reports install progress phases locally', () async {
    final phases = <CliInstallPhase>[];
    final commands = <String>[];
    final installer = CliInstallerService(
      isWindowsOverride: false,
      localRunner: (command) async {
        commands.add(command.commandLine);
        if (command.commandLine == 'which npm') {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '/usr/bin/npm\n',
          );
        }
        if (_isClaudeNpmInstall(command.commandLine) &&
            command.commandLine.contains('/usr/bin/npm')) {
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
      cli: CliTool.claude,
      mode: CliInstallMode.local,
      onProgress: (progress) => phases.add(progress.phase),
    );

    expect(result.success, isTrue, reason: result.message);
    expect(commands.length, 3);
    expect(commands[0], 'which npm');
    expect(_isClaudeNpmInstall(commands[1]), isTrue);
    expect(commands[2], 'which claude');
    expect(phases, [
      CliInstallPhase.checkingNpm,
      CliInstallPhase.installingCli,
      CliInstallPhase.locatingExecutable,
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
        if (command.commandLine ==
            r"cmd /c 'C:\Program Files\nodejs\npm.cmd' install -g @anthropic-ai/claude-code") {
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
      cli: CliTool.claude,
      mode: CliInstallMode.local,
    );

    expect(result.success, isTrue);
    expect(
      result.executablePath,
      r'C:\Users\alice\AppData\Roaming\npm\claude.cmd',
    );
    expect(commands, [
      'where npm',
      r"cmd /c 'C:\Program Files\nodejs\npm.cmd' install -g @anthropic-ai/claude-code",
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
        if (command.commandLine ==
            r"cmd /c 'C:\Program Files\nodejs\npm.cmd' install -g @anthropic-ai/claude-code") {
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
      cli: CliTool.claude,
      mode: CliInstallMode.local,
    );

    expect(result.success, isTrue);
    expect(result.executablePath, 'wsl.exe /home/alice/.npm-global/bin/claude');
    expect(commands, [
      'where npm',
      r"cmd /c 'C:\Program Files\nodejs\npm.cmd' install -g @anthropic-ai/claude-code",
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
        if (command.commandLine == 'which npm') {
          return const CliInstallerCommandResult(exitCode: 1);
        }
        if (command.commandLine == "bash -ilc 'command -v npm'") {
          return const CliInstallerCommandResult(exitCode: 1);
        }
        if (command.commandLine == "zsh -ilc 'command -v npm'") {
          return const CliInstallerCommandResult(exitCode: 1);
        }
        if (command.commandLine.contains('nodejs.org/dist/')) {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '10.9.0\n',
          );
        }
        if (command.commandLine.contains('export PATH=') &&
            _isClaudeNpmInstall(command.commandLine)) {
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
      cli: CliTool.claude,
      mode: CliInstallMode.local,
    );

    expect(result.success, isTrue);
    expect(result.executablePath, '/home/alice/.local/bin/claude');
    expect(commands[0], 'which npm');
    expect(commands.any((line) => line.contains('nodejs.org/dist/')), isTrue);
    expect(commands.any(_isClaudeNpmInstall), isTrue);
  });

  test('uses login-shell npm on Unix when bare which misses', () async {
    final commands = <String>[];
    final installer = CliInstallerService(
      isWindowsOverride: false,
      localRunner: (command) async {
        commands.add(command.commandLine);
        if (command.commandLine == 'which npm') {
          return const CliInstallerCommandResult(exitCode: 1);
        }
        if (command.commandLine == "bash -ilc 'command -v npm'") {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '/opt/homebrew/bin/npm\n',
          );
        }
        if (_isClaudeNpmInstall(command.commandLine) &&
            command.commandLine.contains('/opt/homebrew/bin/npm')) {
          return const CliInstallerCommandResult(exitCode: 0);
        }
        if (command.commandLine == 'which claude') {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '/opt/homebrew/bin/claude\n',
          );
        }
        return const CliInstallerCommandResult(exitCode: 127);
      },
    );

    final result = await installer.install(
      cli: CliTool.claude,
      mode: CliInstallMode.local,
    );

    expect(result.success, isTrue, reason: result.message);
    expect(result.executablePath, '/opt/homebrew/bin/claude');
    expect(commands.length, 4);
    expect(commands[0], 'which npm');
    expect(commands[1], "bash -ilc 'command -v npm'");
    expect(_isClaudeNpmInstall(commands[2]), isTrue);
    expect(commands[3], 'which claude');
    expect(commands.any((line) => line.contains('nodejs.org')), isFalse);
  });

  test('reports local npm install failure', () async {
    final installer = CliInstallerService(
      isWindowsOverride: false,
      localRunner: (command) async {
        if (command.commandLine == 'which npm') {
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
      cli: CliTool.claude,
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
        if (_isTermuxProbe(command.commandLine)) {
          return _termuxProbeNotTermux();
        }
        if (command.commandLine == 'command -v npm') {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '/usr/bin/npm\n',
          );
        }
        if (_isNpmVersionProbe(command.commandLine) &&
            command.commandLine.contains('/usr/bin/npm')) {
          return const CliInstallerCommandResult(exitCode: 0);
        }
        if (_isClaudeNpmInstall(command.commandLine) &&
            command.commandLine.contains('/usr/bin/npm')) {
          return const CliInstallerCommandResult(exitCode: 0);
        }
        if (_isRemoteClaudeLocate(command.commandLine)) {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '/home/alice/.npm-global/bin/claude\n',
          );
        }
        return const CliInstallerCommandResult(exitCode: 127);
      },
    );

    final result = await installer.install(
      cli: CliTool.claude,
      mode: CliInstallMode.ssh,
      sshProfile: _profile,
    );

    expect(result.success, isTrue);
    expect(result.executablePath, '/home/alice/.npm-global/bin/claude');
    expect(commands.length, 5);
    expect(_isTermuxProbe(commands[0]), isTrue);
    expect(commands[1], 'command -v npm');
    expect(_isNpmVersionProbe(commands[2]), isTrue);
    expect(_isClaudeNpmInstall(commands[3]), isTrue);
    expect(_isRemoteClaudeLocate(commands[4]), isTrue);
  });

  test('bootstraps Node npm on SSH host when npm is missing', () async {
    final commands = <String>[];
    final installer = CliInstallerService(
      sshRunner: (profile, command) async {
        commands.add(command.commandLine);
        if (_isTermuxProbe(command.commandLine)) {
          return _termuxProbeNotTermux();
        }
        if (command.commandLine == 'command -v npm') {
          return const CliInstallerCommandResult(exitCode: 1);
        }
        if (command.commandLine == "bash -ilc 'command -v npm'") {
          return const CliInstallerCommandResult(exitCode: 1);
        }
        if (command.commandLine == "zsh -ilc 'command -v npm'") {
          return const CliInstallerCommandResult(exitCode: 1);
        }
        if (_isPrefixAwareNpmLocate(command.commandLine)) {
          return const CliInstallerCommandResult(exitCode: 1);
        }
        if (command.commandLine.contains('nodejs.org/dist/')) {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout:
                '/home/alice/.local/share/com.hhoa.teampilot/toolchain/node/v24.15.0/bin/npm\n',
          );
        }
        if (_isClaudeNpmInstall(command.commandLine)) {
          return const CliInstallerCommandResult(exitCode: 0);
        }
        if (_isRemoteClaudeLocate(command.commandLine)) {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '/home/alice/.local/bin/claude\n',
          );
        }
        return const CliInstallerCommandResult(exitCode: 127);
      },
    );

    final result = await installer.install(
      cli: CliTool.claude,
      mode: CliInstallMode.ssh,
      sshProfile: _profile,
    );

    expect(result.success, isTrue, reason: result.message);
    expect(result.executablePath, '/home/alice/.local/bin/claude');
    expect(_isTermuxProbe(commands[0]), isTrue);
    expect(commands[1], 'command -v npm');
    expect(commands.any((line) => line.contains('nodejs.org/dist/')), isTrue);
    expect(commands.any(_isClaudeNpmInstall), isTrue);
  });

  test(
    'uses login-shell npm on SSH host when bare command -v misses',
    () async {
      final commands = <String>[];
      final installer = CliInstallerService(
        sshRunner: (profile, command) async {
          commands.add(command.commandLine);
          if (_isTermuxProbe(command.commandLine)) {
            return _termuxProbeNotTermux();
          }
          if (command.commandLine == 'command -v npm') {
            return const CliInstallerCommandResult(exitCode: 1);
          }
          if (command.commandLine == "bash -ilc 'command -v npm'") {
            return const CliInstallerCommandResult(
              exitCode: 0,
              stdout: '/opt/homebrew/bin/npm\n',
            );
          }
          if (_isNpmVersionProbe(command.commandLine) &&
              command.commandLine.contains('/opt/homebrew/bin/npm')) {
            return const CliInstallerCommandResult(exitCode: 0);
          }
          if (_isClaudeNpmInstall(command.commandLine) &&
              command.commandLine.contains('/opt/homebrew/bin/npm')) {
            return const CliInstallerCommandResult(exitCode: 0);
          }
          if (_isRemoteClaudeLocate(command.commandLine)) {
            return const CliInstallerCommandResult(
              exitCode: 0,
              stdout: '/opt/homebrew/bin/claude\n',
            );
          }
          return const CliInstallerCommandResult(exitCode: 127);
        },
      );

      final result = await installer.install(
        cli: CliTool.claude,
        mode: CliInstallMode.ssh,
        sshProfile: _profile,
      );

      expect(result.success, isTrue, reason: result.message);
      expect(result.executablePath, '/opt/homebrew/bin/claude');
      expect(commands.length, 6);
      expect(_isTermuxProbe(commands[0]), isTrue);
      expect(commands[1], 'command -v npm');
      expect(commands[2], "bash -ilc 'command -v npm'");
      expect(_isNpmVersionProbe(commands[3]), isTrue);
      expect(_isClaudeNpmInstall(commands[4]), isTrue);
      expect(_isRemoteClaudeLocate(commands[5]), isTrue);
    },
  );

  test('requires an SSH profile for SSH install', () async {
    final installer = CliInstallerService(
      sshRunner: (_, _) async => const CliInstallerCommandResult(exitCode: 0),
    );

    final result = await installer.install(
      cli: CliTool.claude,
      mode: CliInstallMode.ssh,
    );

    expect(result.success, isFalse);
    expect(result.message, contains('SSH'));
  });

  test(
    'installs Cursor CLI locally on Unix via official curl script',
    () async {
      final commands = <String>[];
      final installer = CliInstallerService(
        isWindowsOverride: false,
        localRunner: (command) async {
          commands.add(command.commandLine);
          if (command.commandLine.contains(
            'curl https://cursor.com/install -fsS | bash',
          )) {
            return const CliInstallerCommandResult(exitCode: 0);
          }
          if (command.commandLine == 'which cursor-agent') {
            return const CliInstallerCommandResult(
              exitCode: 0,
              stdout: '/home/alice/.local/bin/cursor-agent\n',
            );
          }
          return const CliInstallerCommandResult(exitCode: 127);
        },
      );

      final result = await installer.install(
        cli: CliTool.cursor,
        mode: CliInstallMode.local,
      );

      expect(result.success, isTrue, reason: result.message);
      expect(result.executablePath, '/home/alice/.local/bin/cursor-agent');
      expect(commands.length, greaterThanOrEqualTo(2));
      expect(commands.any((c) => c.contains('curl https://cursor.com/install')),
          isTrue);
      expect(commands.any((c) => c == 'which cursor-agent'), isTrue);
    },
  );

  test('installs Cursor CLI locally on Windows via PowerShell', () async {
    final commands = <String>[];
    final installer = CliInstallerService(
      isWindowsOverride: true,
      localRunner: (command) async {
        commands.add(command.commandLine);
        if (command.executable == 'powershell' &&
            command.arguments.any(
              (arg) => arg.contains('cursor.com/install?win32=true'),
            )) {
          return const CliInstallerCommandResult(exitCode: 0);
        }
        if (command.commandLine == 'where cursor-agent') {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: r'C:\Users\alice\.local\bin\cursor-agent.cmd',
          );
        }
        return const CliInstallerCommandResult(exitCode: 127);
      },
    );

    final result = await installer.install(
      cli: CliTool.cursor,
      mode: CliInstallMode.local,
    );

    expect(result.success, isTrue, reason: result.message);
    expect(
      result.executablePath,
      r'C:\Users\alice\.local\bin\cursor-agent.cmd',
    );
    expect(commands.length, 2);
    expect(commands[0], contains('cursor.com/install?win32=true'));
    expect(commands[1], 'where cursor-agent');
  });

  test('installs Cursor CLI on SSH host via official curl script', () async {
    final commands = <String>[];
    final installer = CliInstallerService(
      sshRunner: (profile, command) async {
        commands.add(command.commandLine);
        if (_isTermuxProbe(command.commandLine)) {
          return _termuxProbeNotTermux();
        }
        if (_isGlibcProbe(command.commandLine)) {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: 'GLIBC=2.31\n',
          );
        }
        if (command.commandLine.contains(
          'curl https://cursor.com/install -fsS | bash',
        )) {
          return const CliInstallerCommandResult(exitCode: 0);
        }
        if (command.commandLine.startsWith('sh -c') &&
            command.commandLine.contains('command -v cursor-agent')) {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '/home/alice/.local/bin/cursor-agent\n',
          );
        }
        return const CliInstallerCommandResult(exitCode: 127);
      },
    );

    final result = await installer.install(
      cli: CliTool.cursor,
      mode: CliInstallMode.ssh,
      sshProfile: _profile,
    );

    expect(result.success, isTrue, reason: result.message);
    expect(result.executablePath, '/home/alice/.local/bin/cursor-agent');
    expect(commands.length, 4);
    expect(_isTermuxProbe(commands[0]), isTrue);
    expect(_isGlibcProbe(commands[1]), isTrue);
    expect(commands[2], contains('curl https://cursor.com/install'));
    expect(commands[3], startsWith('sh -c'));
  });
}

const _profile = SshProfile(
  id: 'ssh-1',
  name: 'dev',
  host: 'example.com',
  username: 'alice',
);
