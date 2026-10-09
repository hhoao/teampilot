import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/claude/capabilities/acp.dart';
import 'package:teampilot/services/cli/claude/capabilities/acp_adapter_installer.dart';
import 'package:teampilot/services/cli/claude/capabilities/executable.dart';
import 'package:teampilot/services/cli/cli_installer_service.dart';

void main() {
  test('installer reports the adapter npm package and executable', () {
    const installer = ClaudeAcpAdapterInstaller();
    expect(installer.npmPackage, '@agentclientprotocol/claude-agent-acp');
    expect(installer.executableName, 'claude-agent-acp');
    expect(installer.displayName, 'Claude ACP adapter');
    expect(installer.executableName, ClaudeAcpCapability.adapterName);
  });

  test('Claude Code package is unchanged', () {
    expect(
      const ClaudeExecutableCapability().npmPackage,
      '@anthropic-ai/claude-code',
    );
  });

  test(
    'install runs npm for the adapter; locate misses before and hits after',
    () async {
      final commands = <String>[];
      var installed = false;
      final installer = CliInstallerService(
        isWindowsOverride: false,
        localRunner: (command) async {
          final line = command.commandLine;
          commands.add(line);
          if (line == 'which npm') {
            return const CliInstallerCommandResult(
              exitCode: 0,
              stdout: '/usr/bin/npm\n',
            );
          }
          if (line.contains('npm install -g') &&
              line.contains('@agentclientprotocol/claude-agent-acp')) {
            installed = true;
            return const CliInstallerCommandResult(exitCode: 0);
          }
          if (line == 'which claude-agent-acp') {
            return installed
                ? const CliInstallerCommandResult(
                    exitCode: 0,
                    stdout: '/home/u/.local/bin/claude-agent-acp\n',
                  )
                : const CliInstallerCommandResult(exitCode: 1);
          }
          return const CliInstallerCommandResult(exitCode: 127);
        },
      );

      final result = await installer.installAdapter(
        installer: const ClaudeAcpAdapterInstaller(),
        mode: CliInstallMode.local,
      );

      expect(result.success, isTrue);
      expect(result.executablePath, '/home/u/.local/bin/claude-agent-acp');
      expect(installed, isTrue);
      expect(
        commands.any((c) => c.contains('@anthropic-ai/claude-code')),
        isFalse,
      );
    },
  );

  group('locateClaudeAcpAdapter', () {
    test('returns bare name when not installed (fails closed)', () {
      expect(
        locateClaudeAcpAdapter(
          environment: const {'PATH': '/usr/bin:/bin', 'HOME': '/home/u'},
          fileExists: (_) => false,
          isWindows: false,
        ),
        'claude-agent-acp',
      );
    });

    test('prefers PATH hit', () {
      expect(
        locateClaudeAcpAdapter(
          environment: const {'PATH': '/usr/bin:/opt/bin', 'HOME': '/home/u'},
          fileExists: (p) => p == '/opt/bin/claude-agent-acp',
          isWindows: false,
        ),
        '/opt/bin/claude-agent-acp',
      );
    });

    test('falls back to ~/.local/bin after install', () {
      expect(
        locateClaudeAcpAdapter(
          environment: const {'PATH': '/usr/bin', 'HOME': '/home/u'},
          fileExists: (p) => p == '/home/u/.local/bin/claude-agent-acp',
          isWindows: false,
        ),
        '/home/u/.local/bin/claude-agent-acp',
      );
    });

    test('locator is never an installer: lookup does not install', () {
      var probes = 0;
      final cap = ClaudeAcpCapability(
        locateAdapter: (_) => locateClaudeAcpAdapter(
          environment: const {'PATH': '/usr/bin', 'HOME': '/home/u'},
          fileExists: (_) {
            probes++;
            return false;
          },
          isWindows: false,
        ),
      );
      expect(cap.agentExecutable('/usr/bin/claude'), 'claude-agent-acp');
      expect(probes, greaterThan(0));
    });
  });
}
