import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/codex/capabilities/acp.dart';
import 'package:teampilot/services/cli/codex/capabilities/acp_adapter_installer.dart';
import 'package:teampilot/services/cli/codex/capabilities/executable.dart';
import 'package:teampilot/services/cli/cli_installer_service.dart';

void main() {
  test('installer reports the adapter npm package and executable', () {
    const installer = CodexAcpAdapterInstaller();
    expect(installer.npmPackage, '@agentclientprotocol/codex-acp');
    expect(installer.executableName, 'codex-acp');
    expect(installer.displayName, 'Codex ACP adapter');
    expect(installer.executableName, CodexAcpCapability.adapterName);
  });

  test('Codex CLI package is unchanged', () {
    expect(const CodexExecutableCapability().npmPackage, '@openai/codex');
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
              line.contains('@agentclientprotocol/codex-acp')) {
            installed = true;
            return const CliInstallerCommandResult(exitCode: 0);
          }
          if (line == 'which codex-acp') {
            return installed
                ? const CliInstallerCommandResult(
                    exitCode: 0,
                    stdout: '/home/u/.local/bin/codex-acp\n',
                  )
                : const CliInstallerCommandResult(exitCode: 1);
          }
          return const CliInstallerCommandResult(exitCode: 127);
        },
      );

      final result = await installer.installAdapter(
        installer: const CodexAcpAdapterInstaller(),
        mode: CliInstallMode.local,
      );

      expect(result.success, isTrue);
      expect(result.executablePath, '/home/u/.local/bin/codex-acp');
      expect(installed, isTrue);
      expect(commands.any((c) => c.contains('@openai/codex')), isFalse);
    },
  );

  group('locateCodexAcpAdapter', () {
    test('returns bare name when not installed (fails closed)', () {
      expect(
        locateCodexAcpAdapter(
          environment: const {'PATH': '/usr/bin:/bin', 'HOME': '/home/u'},
          fileExists: (_) => false,
          isWindows: false,
        ),
        'codex-acp',
      );
    });

    test('prefers PATH hit', () {
      expect(
        locateCodexAcpAdapter(
          environment: const {'PATH': '/usr/bin:/opt/bin', 'HOME': '/home/u'},
          fileExists: (p) => p == '/opt/bin/codex-acp',
          isWindows: false,
        ),
        '/opt/bin/codex-acp',
      );
    });

    test('falls back to ~/.local/bin after install', () {
      expect(
        locateCodexAcpAdapter(
          environment: const {'PATH': '/usr/bin', 'HOME': '/home/u'},
          fileExists: (p) => p == '/home/u/.local/bin/codex-acp',
          isWindows: false,
        ),
        '/home/u/.local/bin/codex-acp',
      );
    });

    test(
      'returns TeamPilot node prefix path when only that file exists',
      () {
        expect(
          locateCodexAcpAdapter(
            environment: const {'PATH': '/usr/bin', 'HOME': '/home/u'},
            fileExists: (p) =>
                p ==
                '/home/u/.local/share/com.hhoa.teampilot/toolchain/node/current/bin/codex-acp',
            isWindows: false,
          ),
          '/home/u/.local/share/com.hhoa.teampilot/toolchain/node/current/bin/codex-acp',
        );
      },
    );

    test('locator is never an installer: lookup does not install', () {
      var probes = 0;
      final cap = CodexAcpCapability(
        locateAdapter: (_) => locateCodexAcpAdapter(
          environment: const {'PATH': '/usr/bin', 'HOME': '/home/u'},
          fileExists: (_) {
            probes++;
            return false;
          },
          isWindows: false,
        ),
      );
      expect(cap.agentExecutable('/usr/bin/codex'), 'codex-acp');
      expect(probes, greaterThan(0));
    });
  });
}
