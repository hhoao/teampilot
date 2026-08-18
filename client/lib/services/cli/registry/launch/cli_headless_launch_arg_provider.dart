import '../cli_capability.dart';
import 'cli_headless_launch_context.dart';
import 'cli_launch_arg_contribution.dart';

/// Capability that contributes semantic fragments to a headless CLI argv.
abstract interface class CliHeadlessLaunchArgProvider implements CliCapability {
  Iterable<CliLaunchArgContribution> buildHeadlessLaunchArgs(
    CliHeadlessLaunchContext context,
  );
}
