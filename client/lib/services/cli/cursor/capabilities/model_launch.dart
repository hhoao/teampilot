import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_context.dart';

final class CursorModelLaunch implements CliLaunchArgProvider {
  const CursorModelLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  ) sync* {
    final model = context.member.model.trim();
    // Auto is cursor-agent's default; omit --model so startup does not fight
    // cli-config. Explicit picker ids (composer-2.5, cursor-grok-4.6-high, …)
    // are passed on the argv so cursor-agent cannot revert to Auto after load.
    if (model.isEmpty || model == 'auto') return;

    yield CliLaunchArgContribution(
      key: 'cursor-model',
      phase: LaunchArgPhase.model,
      args: ['--model', model],
    );
  }
}
