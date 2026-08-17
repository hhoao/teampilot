import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_context.dart';

final class FlashskyaiPromptLaunch implements CliLaunchArgProvider {
  const FlashskyaiPromptLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  ) sync* {
    final appendFile = context.appendSystemPromptFile?.trim() ?? '';
    if (appendFile.isEmpty) return;
    yield CliLaunchArgContribution(
      key: 'flashskyai-prompt',
      phase: LaunchArgPhase.user,
      args: ['--append-system-prompt-file', appendFile],
    );
  }
}
