import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_context.dart';

final class CodexModelLaunch implements CliLaunchArgProvider {
  const CodexModelLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  ) sync* {
    final model = context.member.model.trim();
    if (model.isEmpty) return;

    yield CliLaunchArgContribution(
      key: 'codex-model',
      phase: LaunchArgPhase.model,
      args: ['-m', model],
    );
  }
}
