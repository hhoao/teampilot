import '../cli_capability.dart';
import 'cli_launch_context.dart';

/// A launch capability that validates semantic inputs without contributing
/// argv. This is used for capabilities materialized in config or environment.
abstract interface class CliLaunchConstraint implements CliCapability {
  void validateLaunch(CliLaunchContext context);
}
