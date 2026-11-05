import 'dart:async';
import 'dart:typed_data';

import '../../../models/ssh_profile.dart';
import '../../chat/team_bus/remote/reverse_tunnel.dart';
import '../ssh_forward_channel.dart';
import 'ssh_profile_worker_manager.dart';
import 'ssh_worker_protocol.dart';

/// UI-side primitive forwarding session backed by one profile-worker lease.
final class SshWorkerForwardSession {
  SshWorkerForwardSession({
    required SshProfile profile,
    required SshProfileWorkerLease lease,
    required SshWorkerDialTarget target,
    required Duration timeout,
  }) : _profile = profile,
       _lease = lease,
       _target = target,
       _timeout = timeout {
    _events = lease.events.listen(
      _onEvent,
      onDone: () => unawaited(
        _finish(error: const SshWorkerForwardException('transport_closed')),
      ),
    );
  }

  final SshProfile _profile;
  final SshProfileWorkerLease _lease;
  final SshWorkerDialTarget _target;
  final Duration _timeout;
  final Map<String, _SshWorkerForwardChannelProxy> _channels = {};
  late final StreamSubscription<SshWorkerEvent> _events;
  _SshWorkerReverseTunnelProxy? _reverseTunnel;
  String? _forwardId;
  var _closed = false;
  Future<void>? _closeFuture;

  Future<SshForwardByteChannel> openLocal(String host, int port) async {
    final forwardId = _beginForward();
    final channel = _SshWorkerForwardChannelProxy(
      id: forwardId,
      writeRemote: (data) => _write(forwardId, data),
      closeRemote: close,
      acknowledge: (sequence) => _acknowledge(forwardId, sequence),
      onFinished: () => _channels.remove(forwardId),
    );
    _channels[forwardId] = channel;
    try {
      final reply = await _request(SshWorkerOperation.openForwardLocal, {
        ..._openArgs(forwardId),
        'host': host,
        'port': port,
      });
      _expectSuccess(reply);
      return channel;
    } on Object {
      await _finish(error: const SshWorkerForwardException('open_failed'));
      rethrow;
    }
  }

  Future<ReverseTunnel> openRemote(String bindHost) async {
    final forwardId = _beginForward();
    final tunnel = _SshWorkerReverseTunnelProxy(
      closeRemote: close,
      closeChannel: _closeChannel,
      writeChannel: _write,
      acknowledge: _acknowledge,
      onChannelFinished: (id) => _channels.remove(id),
    );
    _reverseTunnel = tunnel;
    try {
      final reply = await _request(SshWorkerOperation.openForwardRemote, {
        ..._openArgs(forwardId),
        'bindHost': bindHost,
      });
      final result = _expectSuccess(reply);
      final port = result['port'];
      if (port is! int || port < 1 || port > 65535) {
        throw const SshWorkerForwardException('invalid_remote_port');
      }
      tunnel.completeOpen(port);
      return tunnel;
    } on Object {
      await _finish(error: const SshWorkerForwardException('open_failed'));
      rethrow;
    }
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    final forwardId = _forwardId;
    try {
      if (forwardId != null && !_closed) {
        final reply = await _request(SshWorkerOperation.closeForward, {
          'forwardId': forwardId,
        });
        _expectSuccess(reply);
      }
    } finally {
      await _finish();
    }
  }

  String _beginForward() {
    if (_closed || _forwardId != null) {
      throw StateError('SSH forward session is closed or already open');
    }
    return _forwardId = _lease.resourceId('forward');
  }

  Map<String, Object?> _openArgs(String forwardId) => {
    'forwardId': forwardId,
    'profile': _profile.toJson(),
    'target': _target.toWire(),
    'timeoutMs': _timeout.inMilliseconds,
  };

  Future<void> _write(String channelId, Uint8List data) async {
    for (
      var offset = 0;
      offset < data.length;
      offset += sshWorkerMaxChunkSize
    ) {
      final end = (offset + sshWorkerMaxChunkSize).clamp(0, data.length);
      final reply = await _request(SshWorkerOperation.writeForwardChannel, {
        'channelId': channelId,
      }, payload: Uint8List.sublistView(data, offset, end));
      _expectSuccess(reply);
    }
  }

  Future<void> _acknowledge(String channelId, int sequence) => _request(
    SshWorkerOperation.acknowledgeForwardOutput,
    {'channelId': channelId, 'sequence': sequence},
  ).then<void>(_expectSuccess);

  Future<void> _closeChannel(String channelId) => _request(
    SshWorkerOperation.closeForwardChannel,
    {'channelId': channelId},
  ).then<void>(_expectSuccess);

  Future<SshWorkerReply> _request(
    SshWorkerOperation operation,
    Map<String, Object?> args, {
    Uint8List? payload,
  }) => _lease.send(
    SshWorkerRequest(
      requestId: _lease.resourceId('forward-request'),
      operation: operation,
      args: args,
      payload: payload,
    ),
  );

  Map<String, Object?> _expectSuccess(SshWorkerReply reply) {
    if (reply.kind == SshWorkerReplyKind.success) return reply.result;
    throw SshWorkerForwardException(reply.error?.code ?? 'forward_failed');
  }

  void _onEvent(SshWorkerEvent event) {
    final forwardId = _forwardId;
    if (forwardId == null) return;
    if (event.kind == SshWorkerEventKind.forwardChannelOpened &&
        event.forwardId == forwardId) {
      final channelId = event.channelId!;
      final channel = _reverseTunnel?.addChannel(channelId);
      if (channel != null) _channels[channelId] = channel;
      return;
    }
    if (event.kind == SshWorkerEventKind.outputChunk) {
      _channels[event.streamId]?.accept(event);
      return;
    }
    if (event.kind == SshWorkerEventKind.forwardClosed &&
        event.forwardId == forwardId) {
      unawaited(
        _finish(
          error: event.errorCode == null
              ? null
              : SshWorkerForwardException(event.errorCode!),
        ),
      );
    }
  }

  Future<void> _finish({Object? error}) async {
    if (_closed) return;
    _closed = true;
    final channels = _channels.values.toList(growable: false);
    _channels.clear();
    for (final channel in channels) {
      if (error == null) {
        channel.finish();
      } else {
        channel.finishError(error);
      }
    }
    final tunnel = _reverseTunnel;
    if (tunnel != null) {
      if (error == null) {
        tunnel.finish();
      } else {
        tunnel.finishError(error);
      }
    }
    await _events.cancel();
    await _lease.release();
  }
}

/// Worker reply failure surfaced at the narrow forwarding boundary.
final class SshWorkerForwardException implements SshWorkerCodedException {
  const SshWorkerForwardException(this.code);

  @override
  final String code;

  @override
  String toString() => 'SshWorkerForwardException($code)';
}

final class _SshWorkerReverseTunnelProxy implements ReverseTunnel {
  _SshWorkerReverseTunnelProxy({
    required this.closeRemote,
    required this.closeChannel,
    required this.writeChannel,
    required this.acknowledge,
    required this.onChannelFinished,
  }) {
    unawaited(_port.future.catchError((_) => -1));
  }

  final Future<void> Function() closeRemote;
  final Future<void> Function(String channelId) closeChannel;
  final Future<void> Function(String channelId, Uint8List data) writeChannel;
  final Future<void> Function(String channelId, int sequence) acknowledge;
  final void Function(String channelId) onChannelFinished;
  final StreamController<TunnelChannel> _channels =
      StreamController<TunnelChannel>();
  final Map<String, _SshWorkerForwardChannelProxy> _openChannels = {};
  final Completer<int> _port = Completer<int>();
  Future<void>? _closeFuture;
  var _finished = false;

  @override
  Stream<TunnelChannel> get channels => _channels.stream;

  @override
  Future<int> open() => _port.future;

  void completeOpen(int port) {
    if (!_port.isCompleted) _port.complete(port);
  }

  _SshWorkerForwardChannelProxy? addChannel(String id) {
    if (_finished || _openChannels.containsKey(id)) return null;
    final channel = _SshWorkerForwardChannelProxy(
      id: id,
      writeRemote: (data) => writeChannel(id, data),
      closeRemote: () => closeChannel(id),
      acknowledge: (sequence) => acknowledge(id, sequence),
      onFinished: () {
        _openChannels.remove(id);
        onChannelFinished(id);
      },
    );
    _openChannels[id] = channel;
    _channels.add(channel);
    return channel;
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    try {
      await closeRemote();
    } finally {
      finish();
    }
  }

  void finish() {
    if (_finished) return;
    _finished = true;
    if (!_port.isCompleted) {
      _port.completeError(StateError('Reverse tunnel closed'));
    }
    for (final channel in _openChannels.values.toList(growable: false)) {
      channel.finish();
    }
    _openChannels.clear();
    unawaited(_channels.close());
  }

  void finishError(Object error) {
    if (_finished) return;
    _finished = true;
    if (!_port.isCompleted) _port.completeError(error);
    for (final channel in _openChannels.values.toList(growable: false)) {
      channel.finishError(error);
    }
    _openChannels.clear();
    _channels.addError(error);
    unawaited(_channels.close());
  }
}

final class _SshWorkerForwardChannelProxy
    implements SshForwardByteChannel, TunnelChannel {
  _SshWorkerForwardChannelProxy({
    required this.id,
    required this.writeRemote,
    required this.closeRemote,
    required this.acknowledge,
    required this.onFinished,
  });

  final String id;
  final Future<void> Function(Uint8List data) writeRemote;
  final Future<void> Function() closeRemote;
  final Future<void> Function(int sequence) acknowledge;
  final void Function() onFinished;
  final StreamController<List<int>> _input = StreamController<List<int>>();
  var _nextSequence = 0;
  var _finished = false;
  Future<void>? _closeFuture;

  @override
  Stream<List<int>> get incoming => _input.stream;

  @override
  Stream<List<int>> get input => _input.stream;

  @override
  void add(List<int> data) {
    if (_finished) return;
    unawaited(_writeQuietly(Uint8List.fromList(data)));
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    try {
      await closeRemote();
      finish();
    } on Object catch (error) {
      finishError(error);
      rethrow;
    }
  }

  void accept(SshWorkerEvent event) {
    if (_finished) return;
    if (event.sequence != _nextSequence) {
      finishError(const SshWorkerForwardException('output_sequence'));
      return;
    }
    _nextSequence++;
    final bytes = event.bytes!;
    if (bytes.isNotEmpty) _input.add(bytes);
    if (event.isFinal!) {
      final errorCode = event.errorCode;
      if (errorCode == null) {
        finish();
      } else {
        finishError(SshWorkerForwardException(errorCode));
      }
    } else {
      unawaited(_acknowledgeQuietly(event.sequence!));
    }
  }

  void finish() {
    if (_finished) return;
    _finished = true;
    unawaited(_input.close());
    onFinished();
  }

  void finishError(Object error) {
    if (_finished) return;
    _finished = true;
    _input.addError(error);
    unawaited(_input.close());
    onFinished();
  }

  Future<void> _writeQuietly(Uint8List data) async {
    try {
      await writeRemote(data);
    } on Object catch (error) {
      finishError(error);
    }
  }

  Future<void> _acknowledgeQuietly(int sequence) async {
    try {
      await acknowledge(sequence);
    } on Object {
      // ACKs provide flow control only; a final event may win this race.
    }
  }
}
