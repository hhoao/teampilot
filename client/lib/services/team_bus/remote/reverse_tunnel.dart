import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

/// A reverse (remote→local) tunnel: the remote host binds a loopback port and
/// each inbound connection there surfaces here as a [TunnelChannel]. The SSH
/// detail (dartssh2 `forwardRemote`) lives behind this interface so the pump is
/// testable without a real remote host (see `FakeReverseTunnel` in tests).
abstract class ReverseTunnel {
  /// Opens the remote forward and returns the remote-bound port `<P>`.
  Future<int> open();

  /// One [TunnelChannel] per inbound remote connection.
  Stream<TunnelChannel> get channels;

  Future<void> close();
}

/// A single tunneled connection: bytes from the remote arrive on [input];
/// bytes to the remote go through [add].
abstract class TunnelChannel {
  Stream<List<int>> get input;
  void add(List<int> data);
  Future<void> close();
}

/// [TunnelChannel] over plain stream primitives — the mapping target for any
/// concrete transport (e.g. dartssh2's [SSHForwardChannel]). Kept primitive so
/// the mapping is unit-testable without constructing a real SSH channel.
class StreamTunnelChannel implements TunnelChannel {
  StreamTunnelChannel({
    required Stream<List<int>> input,
    required void Function(List<int> data) onAdd,
    required Future<void> Function() onClose,
  }) : _input = input,
       _onAdd = onAdd,
       _onClose = onClose;

  final Stream<List<int>> _input;
  final void Function(List<int>) _onAdd;
  final Future<void> Function() _onClose;

  @override
  Stream<List<int>> get input => _input;

  @override
  void add(List<int> data) => _onAdd(data);

  @override
  Future<void> close() => _onClose();
}

/// Real reverse tunnel over dartssh2 `forwardRemote(port: 0)`. Thin wrapper:
/// the channel-mapping logic lives in [StreamTunnelChannel] (unit-tested); the
/// end-to-end pump behavior is covered via `FakeReverseTunnel` in tests.
class SshReverseTunnel implements ReverseTunnel {
  SshReverseTunnel(this._client, {this.bindHost = '127.0.0.1'});

  final SSHClient _client;
  final String bindHost;
  SSHRemoteForward? _forward;

  @override
  Future<int> open() async {
    final forward = await _client.forwardRemote(host: bindHost, port: 0);
    if (forward == null) {
      throw StateError('SSH forwardRemote(0) was refused by the remote host');
    }
    _forward = forward;
    return forward.port;
  }

  @override
  Stream<TunnelChannel> get channels {
    final forward = _forward;
    if (forward == null) return const Stream.empty();
    return forward.connections.map(
      (c) => StreamTunnelChannel(
        input: c.stream,
        onAdd: c.sink.add,
        onClose: c.close,
      ),
    );
  }

  @override
  Future<void> close() async {
    final forward = _forward;
    _forward = null;
    if (forward == null) return;
    await forward.close();
  }
}

/// Pipes every [ReverseTunnel] channel to a local loopback socket on
/// [localPort] (the bus raw-socket), bridging a remote member to the local bus.
class TunnelPump {
  TunnelPump({required ReverseTunnel tunnel, required int localPort})
    : _tunnel = tunnel,
      _localPort = localPort;

  final ReverseTunnel _tunnel;
  final int _localPort;
  StreamSubscription<TunnelChannel>? _sub;
  final List<Socket> _localSockets = <Socket>[];

  Future<void> start() async {
    _sub = _tunnel.channels.listen(_onChannel);
  }

  Future<void> _onChannel(TunnelChannel channel) async {
    final Socket socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _localPort,
      );
    } on Object {
      await channel.close();
      return;
    }
    _localSockets.add(socket);

    // remote → local bus
    channel.input.listen(
      socket.add,
      onError: (_) => socket.destroy(),
      onDone: () => socket.destroy(),
      cancelOnError: true,
    );
    // local bus → remote
    socket.listen(
      channel.add,
      onError: (_) => unawaited(_closeChannelQuietly(channel)),
      onDone: () => unawaited(_closeChannelQuietly(channel)),
      cancelOnError: true,
    );
  }

  Future<void> _closeChannelQuietly(TunnelChannel channel) async {
    try {
      await channel.close();
    } on Object {
      // Transport may already be torn down during session cleanup.
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    for (final s in _localSockets) {
      s.destroy();
    }
    _localSockets.clear();
    await _tunnel.close();
  }
}
