import 'dart:io';

/// Fast reachability check before attempting a full SSH connect.
abstract class TcpReachabilityProbe {
  Future<bool> isReachable(String host, int port, {required Duration timeout});
}

class SocketTcpReachabilityProbe implements TcpReachabilityProbe {
  const SocketTcpReachabilityProbe();

  @override
  Future<bool> isReachable(
    String host,
    int port, {
    required Duration timeout,
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      return true;
    } on Object {
      return false;
    } finally {
      socket?.destroy();
    }
  }
}
