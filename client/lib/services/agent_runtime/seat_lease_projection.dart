import '../../cubits/seat_lease_cubit.dart';
import '../agent_status/seat_lease.dart';
import '../cli/registry/capabilities/chat_interaction_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import 'runtime_event.dart';
import 'runtime_event_projection.dart';

/// Projects normalized hook status into [SeatLeaseCubit]:
/// - `backgroundTaskStarted` → acquire a `backgroundTask` lease
///   (id = `tool_use_id`, `acquiredAt` = the envelope time).
/// - `taskNotificationToolUseId` → release that lease (any `<status>`; a
///   failed task is as finished as a completed one).
///
/// `seatIdle` envelopes are deliberately ignored: a member reporting idle
/// at turn end is exactly when a background task is still running. Leases
/// clear on the paired notification, their TTL, or seat teardown.
RuntimeEventProjection seatLeaseProjection({
  required SeatLeaseCubit leases,
  CliToolRegistry? registry,
}) {
  final effectiveRegistry = registry ?? CliToolRegistry.builtIn();
  return RuntimeEventProjection(
    onEvent: (event) {
      final raw = event.raw;
      if (raw == null) return;
      final status = effectiveRegistry
          .capability<ChatInteractionCapability>(event.cli)
          ?.normalize(raw);
      if (status == null) return;
      final startId = status.backgroundTaskStarted
          ? status.toolUseId?.trim() ?? ''
          : '';
      if (startId.isNotEmpty) {
        leases.acquire(
          sessionId: event.seat.sessionId,
          memberId: event.seat.memberId,
          lease: SeatLease(
            kind: SeatLeaseKind.backgroundTask,
            id: startId,
            acquiredAt: event.occurredAt,
          ),
        );
        return;
      }
      final releaseId = status.taskNotificationToolUseId?.trim() ?? '';
      if (releaseId.isNotEmpty) {
        leases.release(
          sessionId: event.seat.sessionId,
          memberId: event.seat.memberId,
          leaseId: releaseId,
        );
      }
    },
  );
}
