import '../../../models/team_config.dart';
import 'cli_capability.dart';

abstract interface class CliToolDefinition {
  CliTool get id;
  bool get isLaunchSupported;

  /// Capabilities are ordered by semantic definition order.
  Iterable<CliCapability> get capabilities;
}
