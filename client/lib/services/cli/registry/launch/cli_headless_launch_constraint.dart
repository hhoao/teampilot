import '../cli_capability.dart';
import 'cli_headless_launch_context.dart';

/// A headless launch capability that validates semantic inputs without
/// contributing argv. Config-backed policies use this boundary.
abstract interface class CliHeadlessLaunchConstraint implements CliCapability {
  void validateHeadlessLaunch(CliHeadlessLaunchContext context);
}
