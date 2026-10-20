/// Seat keep-alive leases cleared with attention on seat/tab dispose.
abstract interface class SeatLeasePort {
  void clearSeat({required String sessionId, required String memberId});

  void clearSession(String sessionId);
}

/// Optional capability for a runtime that detects its own out-of-turn work
/// (ACP: no `session/update` arrives after `end_turn`, so the cubit infers it
/// from a `session/load` reconciliation).
///
/// Separate from [SeatLeasePort] so existing clear-only fakes stay valid; the
/// ACP chat cubit holds the aggregate background lease for the duration of the
/// watch so the seat surfaces "background work running" instead of `done`.
abstract interface class SeatBackgroundLeasePort {
  void acquireBackgroundTask({
    required String sessionId,
    required String memberId,
    required String leaseId,
    required DateTime acquiredAt,
  });

  void releaseBackgroundTask({
    required String sessionId,
    required String memberId,
    required String leaseId,
  });
}
