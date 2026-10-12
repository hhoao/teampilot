import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_context.dart';

/// Interactive TUI has no `--agent` on OpenCode v2 (unknown flag dumps help).
/// The picker selection is stamped into `opencode.json` `"default_agent"`.
/// Headless `opencode run` still accepts `--agent`.
final class OpencodeAgentLaunch implements CliLaunchArgProvider {
  const OpencodeAgentLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  ) => const [];

  Iterable<CliLaunchArgContribution> buildHeadlessLaunchArgs(
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
