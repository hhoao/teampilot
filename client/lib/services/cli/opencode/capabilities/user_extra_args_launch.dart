import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_context.dart';
import '../../registry/launch/user_extra_args_provider.dart';

final class OpencodeUserExtraArgsLaunch implements CliLaunchArgProvider {
  const OpencodeUserExtraArgsLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  ) sync* {
    final teamArgs = splitArgs(context.team.extraArgs);
    if (teamArgs.isNotEmpty) {
      yield CliLaunchArgContribution(
        key: 'opencode-user-extra-args.team',
        phase: LaunchArgPhase.user,
        args: teamArgs,
      );
    }

    final memberArgs = splitArgs(context.member.extraArgs);
    if (memberArgs.isNotEmpty) {
      yield CliLaunchArgContribution(
        key: 'opencode-user-extra-args.member',
        phase: LaunchArgPhase.user,
        args: memberArgs,
      );
    }
  }
}
