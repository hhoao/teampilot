import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/services/cli/cli_tool_locator.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/team_generation/models/team_target_probe.dart';
import 'package:teampilot/services/team_generation/runtime_team_target_probe_runner.dart';

void main() {
  test(
    'probes local CLI availability and version without mutating state',
    () async {
      final commands = <List<String>>[];
      final runner = RuntimeTeamTargetProbeRunner(
        registry: CliToolRegistry.builtIn(),
        targetResolver: (id) async =>
            id == RuntimeTarget.localId ? RuntimeTarget.local() : null,
        localProcessRunner:
            (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
              commands.add([executable, ...arguments]);
              if (arguments.length == 1 && arguments.single == 'claude') {
                return ProcessResult(1, 0, '/usr/local/bin/claude\n', '');
              }
              if (executable == '/usr/local/bin/claude' &&
                  arguments.single == '--version') {
                return ProcessResult(2, 0, 'claude 1.2.3\n', '');
              }
              return ProcessResult(3, 1, '', 'not found');
            },
      );

      final result = await runner.probe(
        workspace: Workspace(
          workspaceId: 'workspace',
          folders: const [],
          createdAt: 1,
          updatedAt: 1,
        ),
        targetId: RuntimeTarget.localId,
        cliValues: const {'claude'},
      );

      expect(result.status, TeamTargetProbeStatus.available);
      final probe = result.probeFor(CliTool.claude.value);
      expect(probe?.available, isTrue);
      expect(probe?.version, 'claude 1.2.3');
      expect(probe?.executableBasename, 'claude');
      expect(commands, hasLength(2));
    },
  );

  test('marks stale target unavailable', () async {
    final runner = RuntimeTeamTargetProbeRunner(
      registry: CliToolRegistry.builtIn(),
      targetResolver: (_) async => null,
    );

    final result = await runner.probe(
      workspace: Workspace(
        workspaceId: 'workspace',
        folders: const [],
        createdAt: 1,
        updatedAt: 1,
      ),
      targetId: 'ssh:missing',
      cliValues: const {'claude'},
    );

    expect(result.status, TeamTargetProbeStatus.unavailable);
    expect(result.cliProbes.single.diagnostic, 'target_not_found');
  });
}
