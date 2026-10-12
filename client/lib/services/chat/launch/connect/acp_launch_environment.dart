import 'dart:io';

import 'package:acpd/acpd.dart' as acpd;

import '../../../../models/app_session.dart';
import '../../../../models/runtime_target.dart';
import '../../../../models/team_config.dart';
import '../../../../models/workspace.dart';
import '../../../acp/acp_frame_logger.dart';
import '../../../acp/acp_mcp_servers.dart';
import '../../../acp/acp_session_runtime.dart';
import '../../team_bus/mcp/teammate_bus_mcp_config.dart';
import '../session/shell_launch_spec.dart';

/// Injected ACP runtime for tests; production builds [AcpSessionRuntime].
typedef AcpRuntimeFactory =
    AcpSessionRuntimeApi Function({
      required AcpFrameLogger logger,
      required CliTool tool,
    });

/// Injected simple-connect contribution env for tests.
typedef AcpContributionEnvBuilder =
    Future<Map<String, String>> Function(
      AppSession session,
      Workspace workspace,
    );

/// Tear-off of [SessionConnectOrchestrator.prepareSimpleConnect] without
/// optional MCP / agent-status args (ACP personal launch does not need them).
typedef AcpSimpleConnectPrepare =
    Future<
      ({
        ShellLaunchSpec shellLaunch,
        List<String> warnings,
        String remoteCliPath,
      })
    >
    Function({
      required AppSession session,
      required Workspace workspace,
      required RuntimeTarget launchTarget,
    });

/// Tear-off shape for mixed-seat [SessionConnectOrchestrator.prepareTeamConnect].
///
/// ACP attach supplies the extra MCP map; bus-idle and agent-status stay on
/// the production wrapper because mixed ACP seats are local.
typedef AcpTeamConnectPrepare =
    Future<
      ({
        ShellLaunchSpec shellLaunch,
        List<String> warnings,
        String remoteCliPath,
      })
    >
    Function({
      required AppSession session,
      required TeamProfile team,
      required TeamMemberConfig member,
      required Workspace workspace,
      required RuntimeTarget launchTarget,
      required String workingDirectory,
      Map<String, Map<String, Object?>>? extraMcpServers,
    });

/// Team staging result member attach passes into the ACP runtime start.
typedef AcpTeamLaunchStaging = ({
  Map<String, String> env,
  List<acpd.McpServer> mcpServers,
  String workingDirectory,
  String memberConfigDir,
});

/// Thrown when TeamBus extra names teammate-bus but none of it maps to ACP.
const String acpTeammateBusUnmappedMessage =
    'ACP teammate-bus MCP did not map to a session server';

/// PATH plus the env from PTY `contributeLaunch` / `stageSimpleSessionLaunch`.
Future<Map<String, String>> prepareAcpLaunchEnvironment({
  required AcpSimpleConnectPrepare prepareSimpleConnect,
  required AppSession session,
  required Workspace workspace,
  required RuntimeTarget launchTarget,
  String? path,
}) async {
  final prepared = await prepareSimpleConnect(
    session: session,
    workspace: workspace,
    launchTarget: launchTarget,
  );
  return {
    'PATH': path ?? Platform.environment['PATH'] ?? '',
    ...prepared.shellLaunch.plan.env,
  };
}

/// PATH plus team `contributeLaunch` env, and ACP `mcpServers` from [extraMcpServers].
///
/// Does not call simple connect. When extra contains teammate-bus and
/// [acpMcpServersFromExtra] yields nothing, throws before staging so attach
/// fails instead of opening a silent seat.
Future<AcpTeamLaunchStaging> prepareAcpTeamLaunchEnvironment({
  required AcpTeamConnectPrepare prepareTeamConnect,
  required AppSession session,
  required TeamProfile team,
  required TeamMemberConfig member,
  required Workspace workspace,
  required RuntimeTarget launchTarget,
  required String workingDirectory,
  Map<String, Map<String, Object?>> extraMcpServers = const {},
  String? path,
}) async {
  final mcpServers = acpMcpServersFromExtra(extraMcpServers);
  if (extraMcpServers.containsKey(teammateBusMcpServerName) &&
      mcpServers.isEmpty) {
    throw StateError(acpTeammateBusUnmappedMessage);
  }
  final prepared = await prepareTeamConnect(
    session: session,
    team: team,
    member: member,
    workspace: workspace,
    launchTarget: launchTarget,
    workingDirectory: workingDirectory,
    extraMcpServers: extraMcpServers,
  );
  final stagedCwd =
      prepared.shellLaunch.launchContext.workingDirectory?.trim() ?? '';
  return (
    env: {
      'PATH': path ?? Platform.environment['PATH'] ?? '',
      ...prepared.shellLaunch.plan.env,
    },
    mcpServers: mcpServers,
    workingDirectory: stagedCwd.isNotEmpty ? stagedCwd : workingDirectory,
    memberConfigDir: prepared.shellLaunch.plan.memberConfigDir,
  );
}
