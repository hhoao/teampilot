import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_executable_discovery.dart';
import 'package:teampilot/services/cli/registry/capabilities/remote_cli_locator_capability.dart';

void main() {
  test('locateLocal discovers each launchable CLI independently', () async {
    final discovery = CliExecutableDiscovery();
    final located = await discovery.locateLocal(
      runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
        if (executable == 'which' || executable == 'where') {
          return ProcessResult(
            0,
            0,
            '/usr/local/bin/${arguments.single}\n',
            '',
          );
        }
        return ProcessResult(1, 1, '', '');
      },
    );

    expect(located[CliTool.claude], '/usr/local/bin/claude');
    expect(located[CliTool.flashskyai], '/usr/local/bin/flashskyai');
    expect(located[CliTool.codex], '/usr/local/bin/codex');
    expect(located[CliTool.opencode], '/usr/local/bin/opencode');
    expect(located[CliTool.cursor], '/usr/local/bin/cursor-agent');
  });

  test('locateRemote probes each CLI over the injected runner', () async {
    final discovery = CliExecutableDiscovery();
    final commands = <String>[];
    final located = await discovery.locateRemote(
      run: (command) async {
        commands.add(command);
        if (command.contains('claude')) {
          return const SshCommandResult(
            exitCode: 0,
            stdout: '/remote/bin/claude\n',
          );
        }
        return const SshCommandResult(exitCode: 1, stdout: '');
      },
    );

    expect(located, {CliTool.claude: '/remote/bin/claude'});
    expect(commands.any((command) => command.contains('claude')), isTrue);
  });

  test('locateRemoteCli resolves a single CLI', () async {
    final discovery = CliExecutableDiscovery();
    final located = await discovery.locateRemoteCli(
      cli: CliTool.claude,
      run: (_) async => const SshCommandResult(
        exitCode: 0,
        stdout: '/remote/bin/claude\n',
      ),
    );

    expect(located, '/remote/bin/claude');
  });
}
