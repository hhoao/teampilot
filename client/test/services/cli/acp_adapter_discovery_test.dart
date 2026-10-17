import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/acp_adapter_discovery.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_executable_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('locateLocal returns only absolute Claude/Codex adapter hits', () async {
    final discovery = AcpAdapterDiscovery(registry: CliToolRegistry.builtIn());
    final located = await discovery.locateLocal(
      environment: const {'PATH': '/opt/bin', 'HOME': '/home/u'},
      fileExists: (p) => p == '/opt/bin/claude-agent-acp',
      isWindows: false,
    );
    expect(located[CliTool.claude], '/opt/bin/claude-agent-acp');
    expect(located.containsKey(CliTool.codex), isFalse);
    expect(located.containsKey(CliTool.cursor), isFalse);
  });

  test('locateRemote maps only separate-adapter CLIs via the probe', () async {
    final discovery = AcpAdapterDiscovery(registry: CliToolRegistry.builtIn());
    final located = await discovery.locateRemote(
      run: (command) async {
        if (command.contains('claude-agent-acp')) {
          return const SshCommandResult(
            exitCode: 0,
            stdout: '/home/u/.local/bin/claude-agent-acp\n',
          );
        }
        return const SshCommandResult(exitCode: 1, stdout: '');
      },
    );

    expect(located[CliTool.claude], '/home/u/.local/bin/claude-agent-acp');
    expect(located.containsKey(CliTool.codex), isFalse);
    expect(located.containsKey(CliTool.cursor), isFalse);
  });
}
