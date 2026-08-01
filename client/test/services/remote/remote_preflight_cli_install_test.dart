import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/cli/registry/capabilities/remote_cli_locator_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/remote/remote_preflight_cli_install.dart';

bool _isTermuxProbe(String command) =>
    command.startsWith('sh -c') &&
    command.contains('is_termux=0') &&
    command.contains('TERMUX=1') &&
    command.contains('TERMUX=0');

bool _isNodeBootstrap(String command) =>
    command.startsWith('sh -c') &&
    command.contains('com.hhoa.teampilot/toolchain/node');

bool _isBareNpmLocate(String command) =>
    command == 'command -v npm' ||
    command == "bash -ilc 'command -v npm'" ||
    command == "zsh -ilc 'command -v npm'" ||
    (command.startsWith('sh -c') &&
        command.contains('export PATH=') &&
        command.contains('command -v npm') &&
        !_isNodeBootstrap(command));

void main() {
  final profile = SshProfile(
    id: 'p1',
    name: 'remote',
    host: 'example.com',
    port: 22,
    username: 'dev',
  );

  test(
    'remote preflight install bootstraps node then npm-installs claude',
    () async {
      final calls = <String>[];
      final install = buildRemotePreflightCliInstall(
        registry: CliToolRegistry.builtIn(),
        profile: profile,
        cli: CliTool.claude,
      );

      final path = await install(
        run: (command) async {
          calls.add(command);
          if (_isTermuxProbe(command)) {
            return const SshCommandResult(exitCode: 0, stdout: 'TERMUX=0\n');
          }
          // Bootstrap scripts embed `command -v npm`; match them first.
          if (_isNodeBootstrap(command)) {
            return const SshCommandResult(exitCode: 0, stdout: '10.0.0\n');
          }
          if (_isBareNpmLocate(command)) {
            return const SshCommandResult(exitCode: 1, stdout: '');
          }
          if (command.contains('npm install -g --prefix') &&
              command.contains('@anthropic-ai/claude-code')) {
            return const SshCommandResult(exitCode: 0, stdout: '');
          }
          if (command.startsWith('sh -c') &&
              command.contains('command -v claude')) {
            return const SshCommandResult(
              exitCode: 0,
              stdout: '/home/dev/.local/bin/claude\n',
            );
          }
          return const SshCommandResult(exitCode: 1, stdout: '');
        },
        onProgress: (_) {},
      );

      expect(path, '/home/dev/.local/bin/claude');

      expect(calls.any(_isTermuxProbe), isTrue);
      expect(calls.any(_isNodeBootstrap), isTrue);
      expect(
        calls.any(
          (c) =>
              c.contains('npm install -g --prefix') &&
              c.contains('@anthropic-ai/claude-code'),
        ),
        isTrue,
      );
    },
  );

  test(
    'Node bootstrap failure includes remote stderr in the thrown message',
    () async {
      final install = buildRemotePreflightCliInstall(
        registry: CliToolRegistry.builtIn(),
        profile: profile,
        cli: CliTool.claude,
      );

      await expectLater(
        () => install(
          run: (command) async {
            if (_isTermuxProbe(command)) {
              return const SshCommandResult(exitCode: 0, stdout: 'TERMUX=0\n');
            }
            if (_isNodeBootstrap(command)) {
              return const SshCommandResult(
                exitCode: 1,
                stdout: '',
                stderr: 'curl: (22) The requested URL returned error: 403',
              );
            }
            if (_isBareNpmLocate(command)) {
              return const SshCommandResult(exitCode: 1, stdout: '');
            }
            return const SshCommandResult(exitCode: 1, stdout: '');
          },
          onProgress: (_) {},
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Remote Node/npm install failed'),
              contains('curl: (22) The requested URL returned error: 403'),
            ),
          ),
        ),
      );
    },
  );

  test('preflightSshInstallRunner forwards stderr into command result', () async {
    final runner = preflightSshInstallRunner(profile, (command) async {
      return const SshCommandResult(
        exitCode: 7,
        stdout: 'out-line',
        stderr: 'err-line',
      );
    });
    final result = await runner(
      profile,
      CliInstallerCommand.unixShellScript('true'),
    );
    expect(result.exitCode, 7);
    expect(result.stdout, 'out-line');
    expect(result.stderr, 'err-line');
  });
}
