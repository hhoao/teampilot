import 'dart:io';

import 'package:acpd/acpd.dart' as acpd;

import '../../../../models/app_session.dart';
import '../../../../models/runtime_target.dart';
import '../../../../models/team_config.dart';
import '../../../../models/workspace.dart';
import '../../../../utils/logging/logger.dart';
import '../../../acp/acp_frame_logger.dart';
import '../../../acp/acp_mcp_servers.dart';
import '../../../acp/acp_session_runtime.dart';
import '../../../agent_status/member_agent_status_endpoint.dart';
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

/// Tear-off of [SessionConnectOrchestrator.prepareSimpleConnect] for a personal
/// ACP launch.
///
/// [extraMcpServers] carries the app-owned servers (catalog, team-composer,
/// session SSH) exactly like the PTY simple-connect path, so config-reading
/// CLIs (opencode/cursor) materialize them even though `session/new` MCP is
/// not forwarded. [agentStatus] drives the question bridge.
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
      Map<String, Map<String, Object?>>? extraMcpServers,
      MemberAgentStatusEndpoint? agentStatus,
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
      MemberAgentStatusEndpoint? agentStatus,
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
///
/// [extraMcpServers] is forwarded to the staging so the seat's config files
/// (`.claude.json`, `opencode.json`, `.cursor/mcp.json`, …) get the app-owned
/// MCP servers. Personal ACP `session/new` MCP forwarding is separate and
/// governed by the CLI's `forwardSessionNewMcpServers`.
Future<Map<String, String>> prepareAcpLaunchEnvironment({
  required AcpSimpleConnectPrepare prepareSimpleConnect,
  required AppSession session,
  required Workspace workspace,
  required RuntimeTarget launchTarget,
  Map<String, Map<String, Object?>> extraMcpServers = const {},
  MemberAgentStatusEndpoint? agentStatus,
  String? path,
}) async {
  final prepared = await prepareSimpleConnect(
    session: session,
    workspace: workspace,
    launchTarget: launchTarget,
    extraMcpServers: extraMcpServers,
    agentStatus: agentStatus,
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
  MemberAgentStatusEndpoint? agentStatus,
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
    agentStatus: agentStatus,
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

/// Result shape of `prepareSimpleConnect` / `prepareTeamConnect`.
typedef AcpPreparedSimpleConnect = ({
  ShellLaunchSpec shellLaunch,
  List<String> warnings,
  String remoteCliPath,
});

/// Test seam: skips the production remote staging (`prepareSimpleConnect`).
typedef AcpRemoteStagingBuilder = Future<AcpPreparedSimpleConnect> Function({
  required AppSession session,
  required Workspace workspace,
  required RuntimeTarget launchTarget,
});

/// Values the personal ACP cubit starts with.
typedef AcpPersonalLaunch = ({
  Map<String, String> env,
  String executable,
  String sessionToolDir,
});

/// Selects remote personal ACP launch values from the staging result.
///
/// The staged work-plane env already carries the remote `PATH` and config
/// dirs, so it is used verbatim — never overwritten with the local `PATH`.
/// Empty remote values fall back to the local CLI path / home-plane session
/// tool dir so a partially populated stager cannot start a session with an
/// empty executable.
AcpPersonalLaunch selectAcpRemoteLaunch({
  required AcpPreparedSimpleConnect prepared,
  required String localExecutable,
  required String localSessionToolDir,
}) {
  final remoteCli = prepared.remoteCliPath.trim();
  final memberConfigDir = prepared.shellLaunch.plan.memberConfigDir.trim();
  if (remoteCli.isEmpty) {
    appLogger.w(
      '[acp-remote] empty remote CLI path; falling back to the local '
      'executable for a remote launch',
    );
  }
  if (memberConfigDir.isEmpty) {
    appLogger.w(
      '[acp-remote] empty remote member config dir; falling back to the '
      'session tool dir for a remote launch',
    );
  }
  return (
    env: Map<String, String>.of(prepared.shellLaunch.plan.env),
    executable: remoteCli.isEmpty ? localExecutable : remoteCli,
    sessionToolDir: memberConfigDir.isEmpty
        ? localSessionToolDir
        : memberConfigDir,
  );
}
