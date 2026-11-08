import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/cli/antigravity/capabilities/executable.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/cli/registry/installer/installer_context.dart';

import '../fake_cli_installer_host.dart';

void main() {
  test('executable defaults to agy and supports local install', () {
    const cap = AntigravityExecutableCapability();
    expect(cap.defaultExecutableName, 'agy');
    expect(cap.preferencesPathKey, 'cli.antigravity.path');
    expect(cap.supportsInstaller, isTrue);
  });

  test('ssh install runs the official script and locates agy', () async {
    final host = FakeCliInstallerHost(
      sshResponses: (command) {
        if (command.commandLine.contains('install.sh')) {
          return const CliInstallerCommandResult(exitCode: 0);
        }
        if (command.commandLine.contains('command -v agy')) {
          return const CliInstallerCommandResult(
            exitCode: 0,
            stdout: '/home/dev/.local/bin/agy\n',
          );
        }
        return const CliInstallerCommandResult(exitCode: 1);
      },
    );
    const cap = AntigravityExecutableCapability();
    final result = await cap.install(
      CliInstallContext(
        mode: CliInstallMode.ssh,
        host: host,
        hostEnvironment: host.hostEnvironment,
        sshProfile: const SshProfile(
          id: 'p1',
          name: 'box',
          host: 'example.invalid',
          username: 'dev',
        ),
      ),
    );
    expect(result.success, isTrue);
    expect(result.executablePath, '/home/dev/.local/bin/agy');
    expect(host.sshCommands.any((c) => c.contains('install.sh')), isTrue);
  });
}
