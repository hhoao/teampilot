import '../cli_capability.dart';

abstract interface class WaitBeforeStopCapability implements CliCapability {
  /// CLI default when [TeamMemberConfig.forceWaitBeforeStop] is null.
  ///
  /// Cursor returns `false` — its MCP tools have an agent hard limit of ~60s
  /// and cannot block in `wait_for_message`.
  bool get defaultForceWaitBeforeStop;
}
