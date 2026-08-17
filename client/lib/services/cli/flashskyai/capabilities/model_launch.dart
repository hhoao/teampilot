import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_context.dart';

final class FlashskyaiModelLaunch implements CliLaunchArgProvider {
  const FlashskyaiModelLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  ) sync* {
    final provider = context.member.provider.trim();
    final model = context.member.model.trim();
    final agent = context.member.agent.trim();
    if (provider.isEmpty && model.isEmpty && agent.isEmpty) return;

    yield CliLaunchArgContribution(
      key: 'flashskyai-provider-model-agent',
      phase: LaunchArgPhase.model,
      args: [
        if (provider.isNotEmpty) ...['--provider', provider],
        if (model.isNotEmpty) ...['--model', model],
        if (agent.isNotEmpty) ...['--agent', agent],
      ],
    );
  }
}
