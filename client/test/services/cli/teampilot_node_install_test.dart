import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/installer/teampilot_node_install.dart';

void main() {
  const node = TeampilotNodeInstall.standard;

  test('local bootstrap command embeds pinned Node version', () {
    final unix = node.localBootstrapCommand(false);
    expect(unix.commandLine, contains('nodejs.org/dist/'));
    expect(unix.commandLine, contains(TeampilotNodeInstall.version));
    expect(unix.commandLine, contains(r'$HOME/.local/share/teampilot/node'));

    final windows = node.localBootstrapCommand(true);
    expect(windows.executable, 'powershell');
    expect(windows.arguments.last, contains(TeampilotNodeInstall.version));
  });

  test('ssh bootstrap uses unix install script', () {
    final command = node.sshBootstrapCommand();
    expect(command.executable, 'sh');
    final script = command.arguments.last;
    expect(script, contains('nodejs.org/dist/'));
    expect(script, contains(TeampilotNodeInstall.version));
  });

  test('bootstrapped local package install references teampilot node path', () {
    final unix = node.bootstrappedLocalPackageInstall(
      isWindows: false,
      package: '@anthropic-ai/claude-code',
    );
    expect(
      unix.commandLine,
      contains(
        '\$HOME/.local/share/teampilot/node/${TeampilotNodeInstall.version}/bin/npm install -g @anthropic-ai/claude-code',
      ),
    );

    final windows = node.bootstrappedLocalPackageInstall(
      isWindows: true,
      package: '@anthropic-ai/claude-code',
    );
    final psCommand = windows.arguments.last;
    expect(psCommand, contains('teampilot\\node\\${TeampilotNodeInstall.version}'));
    expect(psCommand, contains('@anthropic-ai/claude-code'));
  });

  test('remote package install uses npm global install argv', () {
    final command = node.remotePackageInstall(
      npmCommand: '/usr/bin/npm',
      package: 'some-package',
    );
    expect(command.executable, '/usr/bin/npm');
    expect(command.arguments, ['install', '-g', 'some-package']);
  });

  test('bootstrapped unix npm path is stable', () {
    expect(
      TeampilotNodeInstall.bootstrappedUnixNpmPath,
      r'$HOME/.local/share/teampilot/node/v24.15.0/bin/npm',
    );
  });
}
