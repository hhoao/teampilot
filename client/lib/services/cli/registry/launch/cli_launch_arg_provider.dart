import '../cli_capability.dart';
import 'cli_launch_arg_contribution.dart';
import 'cli_launch_context.dart';

/// Capability that contributes semantic fragments to a CLI launch argv.
abstract interface class CliLaunchArgProvider implements CliCapability {
  Iterable<CliLaunchArgContribution> buildLaunchArgs(CliLaunchContext context);
}
