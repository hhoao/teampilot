import '../../artifacts/artifact_transfer_service.dart';
import '../../team_bus.dart';

/// Shared dependencies for teammate-bus MCP tool handlers.
class TeammateBusToolContext {
  const TeammateBusToolContext({
    required this.bus,
    required this.idGenerator,
    this.artifacts,
    this.onEnteredWaitLoop,
  });

  final TeamBus bus;
  final String Function() idGenerator;
  final ArtifactTransferService? artifacts;

  /// Clears the idle-stop fuse when a member enters `wait_for_message`.
  final void Function(String memberId)? onEnteredWaitLoop;
}
