/// Seat keep-alive leases cleared with attention on seat/tab dispose.
abstract interface class SeatLeasePort {
  void clearSeat({required String sessionId, required String memberId});

  void clearSession(String sessionId);
}
