import '../../cli_tool_adapter.dart';
import '../cli_capability.dart';
import 'cli_launch_arg_contribution.dart';

/// Capability that contributes semantic fragments to a CLI launch argv.
abstract interface class CliLaunchArgProvider implements CliCapability {
  Iterable<CliLaunchArgContribution> buildLaunchArgs(CliLaunchContext context);
}
