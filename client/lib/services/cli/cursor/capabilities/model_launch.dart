import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_context.dart';

/// Cursor interactive / headless launch no longer passes `--model`.
///
/// Picker ids are stamped into isolated `cli-config.json` via
/// [CursorLaunchModel] during home provision. Passing `--model` made
/// cursor-agent exit when its live catalog was still empty
/// (`Cannot use this model: … Available models:`). Cursor now keeps the
/// stamped selection without argv, so we omit the flag.
final class CursorModelLaunch implements CliLaunchArgProvider {
  const CursorModelLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  ) sync* {
    // Intentionally empty — model comes from stamped cli-config only.
  }
}
