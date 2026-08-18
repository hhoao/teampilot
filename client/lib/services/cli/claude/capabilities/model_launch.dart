import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_context.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';

final class ClaudeModelLaunch implements CliLaunchArgProvider {
  const ClaudeModelLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  ) sync* {
    final model = context.member.model.trim();
    final settings = context.settingsPath?.trim() ?? '';
    if (model.isEmpty && settings.isEmpty) return;

    yield CliLaunchArgContribution(
      key: 'claude-model-settings',
      phase: LaunchArgPhase.model,
      args: [
        if (model.isNotEmpty) ...['--model', model],
        if (settings.isNotEmpty) ...['--settings', settings],
      ],
    );
  }
}
