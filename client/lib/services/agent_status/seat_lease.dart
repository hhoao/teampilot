import 'package:equatable/equatable.dart';

/// Why a seat's underlying CLI process must stay alive beyond the attention
/// turn (`working` / `waiting` / `done`). A `done` seat can hold leases —
/// e.g. its CLI answered, then parked waiting on a background shell task.
enum SeatLeaseKind {
  /// Incrementally acquired from a `PreToolUse(Bash, run_in_background)` and
  /// released by the paired `<task-notification>`. Id = `tool_use_id`.
  backgroundTask,

  /// Authoritative in-flight background work snapshotted by the CLI itself
  /// (claude `Stop` / `SubagentStop` `background_tasks[]`). Replaced wholesale
  /// on every snapshot — ids come from the CLI's task list.
  inFlightTask,
}

/// One keep-alive hold on a seat's CLI process.
class SeatLease extends Equatable {
  const SeatLease({
    required this.kind,
    required this.id,
    required this.acquiredAt,
  });

  final SeatLeaseKind kind;

  /// Pairing key — for [SeatLeaseKind.backgroundTask] the `tool_use_id` of
  /// the starting `PreToolUse`.
  final String id;

  final DateTime acquiredAt;

  @override
  List<Object?> get props => [kind, id, acquiredAt];
}

/// Safety net for leases whose terminal event never arrives (CLI crash
/// before re-invocation, task killed via TaskStop, hook POST lost).
/// Event-paired leases normally clear long before this.
Duration seatLeaseTtl(SeatLeaseKind kind) => switch (kind) {
  SeatLeaseKind.backgroundTask => const Duration(minutes: 60),
  SeatLeaseKind.inFlightTask => const Duration(minutes: 60),
};
