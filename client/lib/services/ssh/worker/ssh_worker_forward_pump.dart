import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'ssh_worker_protocol.dart';

/// Worker-local byte channel surface for SSH forwarding.
abstract interface class SshWorkerForwardChannel {
  Stream<Uint8List> get stream;
  void add(Uint8List data);
  Future<void> close();
}

/// Keeps the dartssh2 forward channel entirely within the worker isolate.
final class DartSshWorkerForwardChannel implements SshWorkerForwardChannel {
  DartSshWorkerForwardChannel(this._channel);

  final SSHForwardChannel _channel;

  @override
  Stream<Uint8List> get stream => _channel.stream;

  @override
  void add(Uint8List data) => _channel.sink.add(data);

  @override
  Future<void> close() => _channel.close();
}

/// Bounded, ordered primitive-byte publisher for one forward channel.
final class SshWorkerForwardPump {
  SshWorkerForwardPump({
    required this.id,
    required this.channel,
    required this.sendEvent,
    required this.onFinished,
    this.outputWindow = 4,
  });

  final String id;
  final SshWorkerForwardChannel channel;
  final void Function(SshWorkerEvent event) sendEvent;
  final void Function(String? errorCode) onFinished;
  final int outputWindow;
  final Set<int> _outstanding = {};
  final List<Uint8List> _pending = [];
  final Completer<void> _finished = Completer<void>();
  StreamSubscription<Uint8List>? _subscription;
  Completer<void>? _pendingDrain;
  var _sequence = 0;
  var _paused = false;
  var _closing = false;
  var _discardPending = false;
  Future<void>? _finishFuture;

  Future<void> get done => _finished.future;

  void start() {
    if (_subscription != null) return;
    _subscription = channel.stream.listen(
      _emit,
      onError: (_, __) => unawaited(_finish(errorCode: 'transport_error')),
      onDone: () => unawaited(_finish()),
      cancelOnError: true,
    );
  }

  void write(Uint8List data) {
    if (!_closing && !_finished.isCompleted) channel.add(data);
  }

  void acknowledge(int sequence) {
    if (_outstanding.remove(sequence)) {
      if (_paused) _resume();
      _drain();
      _completePendingDrainIfReady();
    }
  }

  Future<void> close() async {
    if (!_closing && !_finished.isCompleted) {
      _closing = true;
      _discardPending = true;
      _pending.clear();
      _completePendingDrainIfReady();
      if (_paused) _resume();
      try {
        await channel.close();
      } on Object {
        // The stream completion path remains authoritative for proxy cleanup.
      }
    }
    await _finish();
  }

  void _emit(Uint8List bytes) {
    if (_closing || _finished.isCompleted) return;
    var offset = 0;
    while (offset < bytes.length) {
      final length = math.min(sshWorkerMaxChunkSize, bytes.length - offset);
      _pending.add(Uint8List.sublistView(bytes, offset, offset + length));
      offset += length;
    }
    _drain();
  }

  void _drain() {
    while (_pending.isNotEmpty &&
        _outstanding.length < outputWindow &&
        !_finished.isCompleted) {
      final bytes = _pending.removeAt(0);
      final sequence = _sequence++;
      _outstanding.add(sequence);
      sendEvent(
        SshWorkerEvent.outputChunk(
          streamId: id,
          sequence: sequence,
          bytes: bytes,
          isFinal: false,
        ),
      );
    }
    if (_pending.isNotEmpty) _pause();
  }

  void _pause() {
    final subscription = _subscription;
    if (_paused || subscription == null) return;
    _paused = true;
    subscription.pause();
  }

  void _resume() {
    final subscription = _subscription;
    if (!_paused || subscription == null) return;
    _paused = false;
    subscription.resume();
  }

  Future<void> _finish({String? errorCode}) async {
    final existing = _finishFuture;
    if (existing != null) {
      await existing;
      return;
    }
    if (_finished.isCompleted) return;
    final future = _finishImpl(errorCode: errorCode);
    _finishFuture = future;
    await future;
  }

  Future<void> _finishImpl({String? errorCode}) async {
    _closing = true;
    if (_discardPending) _pending.clear();
    _drain();
    try {
      await _subscription?.cancel();
      if (!_discardPending && _pending.isNotEmpty) {
        final pendingDrain = _pendingDrain = Completer<void>();
        _completePendingDrainIfReady();
        await pendingDrain.future;
      }
      sendEvent(
        SshWorkerEvent.outputChunk(
          streamId: id,
          sequence: _sequence,
          bytes: Uint8List(0),
          isFinal: true,
          errorCode: errorCode,
        ),
      );
      onFinished(errorCode);
    } finally {
      if (!_finished.isCompleted) _finished.complete();
    }
  }

  void _completePendingDrainIfReady() {
    if (_pending.isNotEmpty) return;
    final pendingDrain = _pendingDrain;
    if (pendingDrain != null && !pendingDrain.isCompleted) {
      pendingDrain.complete();
    }
  }
}
