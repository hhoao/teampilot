import 'dart:io';

import '../../../../models/app_session.dart';
import '../../../../models/runtime_target.dart';
import '../../../../models/team_config.dart';
import '../../../../models/workspace.dart';
import '../../../acp/acp_frame_logger.dart';
import '../../../acp/acp_session_runtime.dart';
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
