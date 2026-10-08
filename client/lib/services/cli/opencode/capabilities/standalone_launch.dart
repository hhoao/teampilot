import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_context.dart';

/// OpenCode v2 shares one background server by default. TeamPilot sessions
/// isolate config, plugins, MCP, and the SQLite store per seat, so every
/// launch must use a private server.
final class OpencodeStandaloneLaunch implements CliLaunchArgProvider {
  const OpencodeStandaloneLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  ) sync* {
    yield CliLaunchArgContribution(
      key: 'opencode-standalone',
      phase: LaunchArgPhase.command,
      args: const ['--standalone'],
    );
  }
}
