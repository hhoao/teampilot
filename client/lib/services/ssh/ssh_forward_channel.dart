import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

import '../chat/team_bus/remote/reverse_tunnel.dart';

/// App-owned byte channel for an SSH local forward.
abstract interface class SshForwardByteChannel {
  Stream<List<int>> get incoming;
  void add(List<int> data);
  Future<void> close();
}

/// Direct dartssh2 adapter retained for connector-injected tests.
/// Production forwarding uses the profile-worker proxy.
final class DartSshForwardByteChannel implements SshForwardByteChannel {
  DartSshForwardByteChannel({
    required SSHClient client,
    required SSHForwardChannel channel,
    void Function()? onClosing,
  }) : _client = client,
       _channel = channel,
       _onClosing = onClosing;

  final SSHClient _client;
  final SSHForwardChannel _channel;
  final void Function()? _onClosing;
  Future<void>? _closeFuture;

  @override
  Stream<List<int>> get incoming => _channel.stream;

  @override
  void add(List<int> data) => _channel.sink.add(data);

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _onClosing?.call();
    try {
      await _channel.close();
    } finally {
      if (!_client.isClosed) await _client.disconnect();
    }
  }
}

/// Direct dartssh2 reverse-tunnel adapter retained for connector-injected
/// tests. Production reverse forwarding is worker-owned.
final class DartSshReverseTunnel implements ReverseTunnel {
  DartSshReverseTunnel(this._client, {this.bindHost = '127.0.0.1'});

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
      (channel) => StreamTunnelChannel(
        input: channel.stream,
        onAdd: channel.sink.add,
        onClose: channel.close,
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
