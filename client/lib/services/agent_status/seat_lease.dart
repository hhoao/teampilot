import 'package:equatable/equatable.dart';

/// Why a seat's underlying CLI process must stay alive beyond the attention
/// turn (`working` / `waiting` / `done`). A `done` seat can hold leases —
/// e.g. its CLI answered, then parked waiting on a background shell task.
enum SeatLeaseKind { backgroundTask }

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
    };
