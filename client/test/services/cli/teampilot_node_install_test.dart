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
    expect(unix.commandLine, contains('npmmirror.com/mirrors/node/'));
    expect(unix.commandLine, contains('attempt \$attempt'));
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

  test('ssh bootstrap uses unix install script with glibc fallback', () {
    final command = node.sshBootstrapCommand();
    expect(command.executable, 'sh');
    final script = command.arguments.last;
    expect(script, contains('nodejs.org/dist/'));
    expect(script, contains('npmmirror.com/mirrors/node/'));
    expect(script, contains('unofficial-builds.nodejs.org'));
    expect(script, contains('linux-x64-glibc-217'));
    expect(script, contains(TeampilotNodeInstall.version));
    expect(script, contains(TeampilotNodeInstall.legacyGlibcVersion));
    expect(script, contains('ldd --version'));
    expect(script, contains('\$base/current'));
    expect(script, contains('attempt \$attempt'));
    expect(script, isNot(contains('npm config set prefix')));
  });

  test('ssh bootstrap prefers Termux pkg nodejs over glibc tarball', () {
    final script = node.sshBootstrapCommand().arguments.last;
    expect(script, contains('pkg install -y nodejs'));
    expect(script, contains('is_termux'));
    final termuxIdx = script.indexOf('pkg install -y nodejs');
    final extractIdx = script.indexOf(r'tar -xJf "$tmp/$archive"');
    expect(termuxIdx, greaterThanOrEqualTo(0));
    expect(extractIdx, greaterThan(termuxIdx));
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
    expect(unix.commandLine, isNot(contains('npm config set prefix')));
    expect(
      unix.commandLine,
      contains(
        r'npm install -g --prefix "$HOME/.local" @anthropic-ai/claude-code',
      ),
    );
    expect(unix.commandLine, contains('export PATH='));
    expect(unix.commandLine, contains('/current/bin:'));

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

  test('bootstrapped unix npm path uses current symlink', () {
    expect(
      TeampilotNodeInstall.bootstrappedUnixNpmPath,
      '${TeampilotNodeInstall.unixToolchainNodeBase}/current/bin/npm',
    );
  });
}
