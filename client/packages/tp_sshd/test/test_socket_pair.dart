import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// Minimal paired in-memory [SSHSocket]. Each end's sink writes are delivered
/// to the other end's stream, and closing or destroying either end shuts the
/// whole pair down.
///
/// Ported from the dartssh2 fork's `test/src/ssh_transport_server_kex_test.dart`
/// (Task 2) so both the client and the server side of a tp_sshd test can run
/// in one isolate without real sockets.
class LoopbackSSHSocket implements SSHSocket {
  LoopbackSSHSocket._();

  /// Creates a connected pair of sockets: writes to either end are readable
  /// from the other, as `(clientEnd, serverEnd)`.
  static (LoopbackSSHSocket, LoopbackSSHSocket) pair() {
    final a = LoopbackSSHSocket._();
    final b = LoopbackSSHSocket._();
    a._peer = b;
    b._peer = a;
    return (a, b);
  }

  late final LoopbackSSHSocket _peer;
  final _controller = StreamController<Uint8List>();
  final _doneCompleter = Completer<void>();
  var _isShutdown = false;

  @override
  Stream<Uint8List> get stream => _controller.stream;

  @override
  // A `StreamSink<Uint8List>` is assignable to `StreamSink<List<int>>` through
  // Dart's covariant generics, which is what lets the peer's controller act as
  // this end's sink.
  StreamSink<List<int>> get sink => _peer._controller.sink;

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  Future<void> close() async {
    _shutdown();
    _peer._shutdown();
  }

  @override
  void destroy() {
    _shutdown();
    _peer._shutdown();
  }

  void _shutdown() {
    if (_isShutdown) return;
    _isShutdown = true;
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    unawaited(_controller.close());
  }

  @override
  Future<void> flush() async {}
}

/// Creates a connected pair of in-memory [SSHSocket]s, as
/// `(clientSocket, serverSocket)`.
(SSHSocket, SSHSocket) loopbackSSHSocketPair() => LoopbackSSHSocket.pair();
