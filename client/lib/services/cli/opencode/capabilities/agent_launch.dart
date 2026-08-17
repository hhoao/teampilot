import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_context.dart';

final class OpencodeAgentLaunch implements CliLaunchArgProvider {
  const OpencodeAgentLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  ) sync* {
    final agent = context.member.agent.trim();
    if (agent.isEmpty) return;

    yield CliLaunchArgContribution(
      key: 'opencode-agent',
      phase: LaunchArgPhase.model,
      args: ['--agent', agent],
    );
  }
}
