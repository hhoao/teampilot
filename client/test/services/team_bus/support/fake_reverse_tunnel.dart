import 'dart:async';

import 'package:teampilot/services/team_bus/remote/reverse_tunnel.dart';

/// In-memory [ReverseTunnel] for tests: [open] returns a fixed port and
/// [emitChannel] injects a remote connection without any real SSH.
class FakeReverseTunnel implements ReverseTunnel {
  FakeReverseTunnel({this.port = 54321});

  final int port;
  final _channels = StreamController<TunnelChannel>.broadcast();
  bool closed = false;

  @override
  Future<int> open() async => port;

  @override
  Stream<TunnelChannel> get channels => _channels.stream;

  void emitChannel(TunnelChannel channel) => _channels.add(channel);

  @override
  Future<void> close() async {
    closed = true;
    await _channels.close();
  }
}

/// In-memory [TunnelChannel]: bytes written by the test arrive on [input];
/// bytes the pump sends back are captured on [sent].
class FakeChannel implements TunnelChannel {
  final _input = StreamController<List<int>>();
  final sent = <int>[];
  final _closed = Completer<void>();

  @override
  Stream<List<int>> get input => _input.stream;

  /// Test → channel (as if the remote member wrote bytes).
  void remoteWrite(List<int> data) => _input.add(data);

  @override
  void add(List<int> data) => sent.addAll(data);

  String get sentText => String.fromCharCodes(sent);

  Future<void> get done => _closed.future;

  @override
  Future<void> close() async {
    if (!_input.isClosed) await _input.close();
    if (!_closed.isCompleted) _closed.complete();
  }
}
