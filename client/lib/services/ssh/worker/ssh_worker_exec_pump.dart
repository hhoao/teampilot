import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'ssh_worker_protocol.dart';

/// The worker-local surface needed to stream a non-PTY SSH exec session.
abstract interface class SshWorkerExecSession {
  Stream<Uint8List> get stdout;
  Stream<Uint8List> get stderr;
  Future<void> get done;
  int? get exitCode;
  void write(Uint8List data);
  void closeStdin();
  void kill(SSHSignal signal);
  void close();
}

/// Adapts a worker-owned dartssh2 session without crossing the isolate seam.
final class DartSshWorkerExecSession implements SshWorkerExecSession {
  DartSshWorkerExecSession(this._session);

  final SSHSession _session;

  @override
  Stream<Uint8List> get stdout => _session.stdout;

  @override
  Stream<Uint8List> get stderr => _session.stderr;

  @override
  Future<void> get done => _session.done;

  @override
  int? get exitCode => _session.exitCode;

  @override
  void write(Uint8List data) => _session.write(data);

  @override
  void closeStdin() => _session.stdin.close();

  @override
  void kill(SSHSignal signal) => _session.kill(signal);

  @override
  void close() => _session.close();
}

/// Streams separate stdout/stderr exec frames without aggregating their output.
final class SshWorkerExecPump {
  SshWorkerExecPump({
    required this.id,
    required this.session,
    required this.sendEvent,
    required this.onFinished,
    this.outputWindow = 4,
  });

  final String id;
  final SshWorkerExecSession session;
  final void Function(SshWorkerEvent event) sendEvent;
  final void Function() onFinished;
  final int outputWindow;
  final Set<int> _outstanding = {};
  final List<_ExecFrame> _pending = [];
  final Completer<void> _finished = Completer<void>();
  final _stdoutDone = Completer<void>();
  final _stderrDone = Completer<void>();
  late final StreamSubscription<Uint8List> _stdoutSubscription;
  late final StreamSubscription<Uint8List> _stderrSubscription;
  Completer<void>? _pendingDrain;
  var _sequence = 0;
  var _started = false;
  var _killRequested = false;
  var _paused = false;
  var _discardPending = false;
  String? _errorCode;

  Future<void> get done => _finished.future;

  void start() {
    if (_started) return;
    _started = true;
    _stdoutSubscription = session.stdout.listen(
      (bytes) => _emit(SshWorkerExecStream.stdout, bytes),
      onDone: () => _completeOnce(_stdoutDone),
      onError: (_, __) {
        _errorCode ??= 'member_output_error';
        _completeOnce(_stdoutDone);
      },
    );
    _stderrSubscription = session.stderr.listen(
      (bytes) => _emit(SshWorkerExecStream.stderr, bytes),
      onDone: () => _completeOnce(_stderrDone),
      onError: (_, __) {
        _errorCode ??= 'member_output_error';
        _completeOnce(_stderrDone);
      },
    );
    unawaited(_finishWhenDone());
  }

  void write(Uint8List data) {
    if (_killRequested || _finished.isCompleted) return;
    session.write(data);
  }

  void closeStdin() {
    if (_killRequested || _finished.isCompleted) return;
    try {
      session.closeStdin();
    } on Object {
      // The session may already be closing.
    }
  }

  void kill() {
    if (_killRequested || _finished.isCompleted) return;
    _killRequested = true;
    try {
      session.kill(SSHSignal.KILL);
    } on Object {
      session.close();
    }
  }

  void acknowledge(int sequence) {
    if (!_outstanding.remove(sequence)) return;
    if (_paused && _outstanding.length < outputWindow) {
      _paused = false;
      _stdoutSubscription.resume();
      _stderrSubscription.resume();
    }
    _drain();
    _completePendingDrainIfReady();
  }

  Future<void> close() {
    if (!_finished.isCompleted) {
      _discardPending = true;
      _pending.clear();
      _completePendingDrainIfReady();
      if (_paused) {
        _paused = false;
        _stdoutSubscription.resume();
        _stderrSubscription.resume();
      }
      session.close();
    }
    return done;
  }

  void _emit(SshWorkerExecStream stream, Uint8List bytes) {
    var offset = 0;
    while (offset < bytes.length && !_finished.isCompleted) {
      final length = math.min(sshWorkerMaxChunkSize, bytes.length - offset);
      _pending.add(
        _ExecFrame(
          stream: stream,
          bytes: Uint8List.sublistView(bytes, offset, offset + length),
        ),
      );
      offset += length;
    }
    _drain();
  }

  Future<void> _finishWhenDone() async {
    try {
      try {
        await session.done;
      } on Object {
        // A close or signal may race channel completion; stream EOF still
        // determines when all output already in flight has been forwarded.
        if (!_killRequested) _errorCode ??= 'member_transport_error';
      }
      await Future.wait([_stdoutDone.future, _stderrDone.future]);
      if (_discardPending) _pending.clear();
      _drain();
      if (!_discardPending && _pending.isNotEmpty) {
        final pendingDrain = _pendingDrain = Completer<void>();
        _completePendingDrainIfReady();
        await pendingDrain.future;
      }
      sendEvent(
        SshWorkerEvent.execOutput(
          streamId: id,
          sequence: _sequence++,
          bytes: Uint8List(0),
          isFinal: true,
          exitCode: session.exitCode ?? -1,
          errorCode: _errorCode,
        ),
      );
    } finally {
      onFinished();
      if (!_finished.isCompleted) _finished.complete();
    }
  }

  static void _completeOnce(Completer<void> completer) {
    if (!completer.isCompleted) completer.complete();
  }

  void _drain() {
    while (_pending.isNotEmpty &&
        _outstanding.length < outputWindow &&
        !_finished.isCompleted) {
      final frame = _pending.removeAt(0);
      final sequence = _sequence++;
      _outstanding.add(sequence);
      sendEvent(
        SshWorkerEvent.execOutput(
          streamId: id,
          sequence: sequence,
          stream: frame.stream,
          bytes: frame.bytes,
        ),
      );
    }
    if ((_pending.isNotEmpty || _outstanding.length >= outputWindow) &&
        !_paused) {
      _paused = true;
      _stdoutSubscription.pause();
      _stderrSubscription.pause();
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

final class _ExecFrame {
  const _ExecFrame({required this.stream, required this.bytes});

  final SshWorkerExecStream stream;
  final Uint8List bytes;
}
