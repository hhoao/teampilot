import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_context.dart';

final class ClaudePromptLaunch implements CliLaunchArgProvider {
  const ClaudePromptLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  ) sync* {
    final appendFile = context.appendSystemPromptFile?.trim() ?? '';
    if (appendFile.isEmpty) return;
    yield CliLaunchArgContribution(
      key: 'claude-prompt',
      phase: LaunchArgPhase.prompt,
      args: ['--append-system-prompt-file', appendFile],
    );
  }
}
