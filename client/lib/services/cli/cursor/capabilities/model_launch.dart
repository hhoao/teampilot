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
    if (model.isEmpty) return;

    yield CliLaunchArgContribution(
      key: 'cursor-model',
      phase: LaunchArgPhase.model,
      args: ['--model', model],
    );
  }
}
