import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/remote_cli_locator_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/remote/remote_preflight_cli_install.dart';

void main() {
  test('remote preflight install bootstraps node then npm-installs claude', () async {
    final profile = SshProfile(
      id: 'p1',
      name: 'remote',
      host: 'example.com',
      port: 22,
      username: 'dev',
    );
    final calls = <String>[];
    final install = buildRemotePreflightCliInstall(
      registry: CliToolRegistry.builtIn(),
      profile: profile,
      cli: CliTool.claude,
    );

    await install(
      run: (command) async {
        calls.add(command);
        if (command.contains('command -v npm')) {
          return const SshCommandResult(exitCode: 1, stdout: '');
        }
        if (command.startsWith('sh -c')) {
          return const SshCommandResult(exitCode: 0, stdout: '10.0.0\n');
        }
        if (command.contains('npm install -g @anthropic-ai/claude-code')) {
          return const SshCommandResult(exitCode: 0, stdout: '');
        }
        if (command.contains('command -v claude')) {
          return const SshCommandResult(
            exitCode: 0,
            stdout: '/home/dev/.local/bin/claude\n',
          );
        }
        return const SshCommandResult(exitCode: 1, stdout: '');
      },
      onProgress: (_) {},
    );

    expect(calls.any((c) => c.startsWith('sh -c')), isTrue);
    expect(
      calls.any((c) => c.contains('npm install -g @anthropic-ai/claude-code')),
      isTrue,
    );
  });
}
