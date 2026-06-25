import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/cli/registry/installer/teampilot_node_install.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

void main() {
  const node = TeampilotNodeInstall.standard;

  test('local bootstrap command embeds pinned Node version', () {
    final unixRunner = HostExecutionEnvironment.resolve(
      isWindowsHost: false,
      storageMode: StorageBackendMode.native,
    ).scriptRunner;
    final unix = node.localBootstrapCommand(unixRunner);
    expect(unix.commandLine, contains('nodejs.org/dist/'));
    expect(unix.commandLine, contains(TeampilotNodeInstall.version));
    expect(
      unix.commandLine,
      contains(TeampilotNodeInstall.unixToolchainNodeBase),
    );

    final windowsRunner = HostExecutionEnvironment.resolve(
      isWindowsHost: true,
      storageMode: StorageBackendMode.native,
    ).scriptRunner;
    final windows = node.localBootstrapCommand(windowsRunner);
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
    final unixRunner = HostExecutionEnvironment.resolve(
      isWindowsHost: false,
      storageMode: StorageBackendMode.native,
    ).scriptRunner;
    final unix = node.bootstrappedLocalPackageInstall(
      runner: unixRunner,
      package: '@anthropic-ai/claude-code',
    );
    expect(
      unix.commandLine,
      contains('npm install -g @anthropic-ai/claude-code'),
    );
    expect(unix.commandLine, contains('export PATH='));

    final windowsRunner = HostExecutionEnvironment.resolve(
      isWindowsHost: true,
      storageMode: StorageBackendMode.native,
    ).scriptRunner;
    final windows = node.bootstrappedLocalPackageInstall(
      runner: windowsRunner,
      package: '@anthropic-ai/claude-code',
    );
    final psCommand = windows.arguments.last;
    expect(
      psCommand,
      contains(
        '${TeampilotNodeInstall.windowsToolchainNodeBase}\\${TeampilotNodeInstall.version}',
      ),
    );
    expect(psCommand, contains('@anthropic-ai/claude-code'));
  });

  test('bootstrapped unix npm path is stable', () {
    expect(
      TeampilotNodeInstall.bootstrappedUnixNpmPath,
      '${TeampilotNodeInstall.unixToolchainNodeBase}/${TeampilotNodeInstall.version}/bin/npm',
    );
  });
}
