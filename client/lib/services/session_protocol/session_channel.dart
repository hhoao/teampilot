/// Transport seam for the session protocol.
///
/// Implementations: SSH `forwardLocal`, in-process tests, and a future
/// WebSocket/Socket adapter. The protocol only needs a reliable ordered byte
/// stream, so it does not import dartssh2.
abstract interface class SessionByteChannel {
  Stream<List<int>> get incoming;
  void add(List<int> data);
  Future<void> close();
}
