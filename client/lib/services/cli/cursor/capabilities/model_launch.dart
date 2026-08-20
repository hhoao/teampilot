import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_context.dart';

final class CursorModelLaunch implements CliLaunchArgProvider {
  const CursorModelLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(CliLaunchContext _) sync* {
    // Variant slugs like `cursor-grok-4.6-high` are stamped into isolated
    // `cli-config.json` (see CursorLaunchModel). Passing `--model` skips
    // cursor-agent's persist-from-config fallback and exits 1 when the live
    // catalog is still empty.
  }
}
