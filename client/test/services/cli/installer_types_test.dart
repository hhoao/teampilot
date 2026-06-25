import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/cli/registry/installer/teampilot_node_install.dart';

void main() {
  group('CliInstallerCommand.unixShellScript', () {
    test('wraps script body in sh -c', () {
      final command = CliInstallerCommand.unixShellScript('echo hi');
      expect(command.executable, 'sh');
      expect(command.arguments, ['-c', 'echo hi']);
      expect(command.commandLine, "sh -c 'echo hi'");
    });
  });

  group('CliInstallerCommand.commandV', () {
    test('builds command -v probe', () {
      final command = CliInstallerCommand.commandV('claude');
      expect(command.commandLine, 'command -v claude');
    });
  });

  group('CliInstallerCommand.npmGlobalInstall', () {
    test('uses direct argv for absolute npm path', () {
      final command = CliInstallerCommand.npmGlobalInstall(
        npmCommand: '/usr/bin/npm',
        package: 'some-package',
      );
      expect(command.executable, '/usr/bin/npm');
      expect(command.arguments, ['install', '-g', 'some-package']);
    });

    test('wraps bootstrapped npm in shell with PATH for node shebang', () {
      final command = CliInstallerCommand.npmGlobalInstall(
        npmCommand: TeampilotNodeInstall.bootstrappedUnixNpmPath,
        package: '@anthropic-ai/claude-code',
      );
      expect(command.executable, 'sh');
      final script = command.arguments.last;
      expect(script, contains('export PATH='));
      expect(script, contains('npm install -g @anthropic-ai/claude-code'));
    });
  });

  group('needsUnixShellInvocation', () {
    test('true when executable contains env var or space', () {
      expect(CliInstallerCommand.needsUnixShellInvocation(r'$HOME/bin/npm'), isTrue);
      expect(CliInstallerCommand.needsUnixShellInvocation('/usr/bin/npm'), isFalse);
    });
  });
}
