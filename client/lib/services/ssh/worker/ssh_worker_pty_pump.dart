import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'ssh_worker_output_batcher.dart';
import 'ssh_worker_protocol.dart';

/// Minimal worker-local PTY session surface used by the output pump.
abstract interface class SshWorkerPtySession {
  Stream<Uint8List> get stdout;
  Stream<Uint8List> get stderr;
  Future<void> get done;
  int? get exitCode;
  void write(Uint8List data);
  void resize(int rows, int columns);
  void close();
}

/// Adapts worker-owned dartssh2 sessions without exposing them to the UI.
final class DartSshWorkerPtySession implements SshWorkerPtySession {
  DartSshWorkerPtySession(this._session);

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
  void close() => _session.close();

  @override
  void resize(int rows, int columns) => _session.resizeTerminal(columns, rows);

  @override
  void write(Uint8List data) => _session.write(data);
}

/// Batches one worker-owned PTY and guarantees a single ordered final event.
final class SshWorkerPtyPump {
  SshWorkerPtyPump({
    required this.id,
    required this.memberId,
    required this.session,
    required this.sendEvent,
    required this.onFinished,
    required this.outputWindow,
    SshWorkerOutputBatcher? batcher,
  }) : _batcher = batcher ?? SshWorkerOutputBatcher();

  final String id;
  final String memberId;
  final SshWorkerPtySession session;
  final void Function(SshWorkerEvent event) sendEvent;
  final void Function() onFinished;
  final int outputWindow;
  final SshWorkerOutputBatcher _batcher;
  final Set<int> _outstanding = {};
  final Completer<void> _finished = Completer<void>();
  late final StreamSubscription<Uint8List> _stdout;
  late final StreamSubscription<Uint8List> _stderr;
  late final StreamSubscription<Uint8List> _batches;
  final _stdoutDone = Completer<void>();
  final _stderrDone = Completer<void>();
  var _sequence = 0;
  var _started = false;
  var _closeRequested = false;
  var _paused = false;
  var _draining = false;
  var _eof = false;
  String? _errorCode;

  Future<void> get done => _finished.future;

  void start() {
    if (_started) return;
    _started = true;
    _batches = _batcher.output.listen(_emit);
    _stdout = session.stdout.listen(
      _batcher.add,
      onDone: () => _completeOnce(_stdoutDone),
      onError: (_, __) {
        _errorCode ??= 'member_output_error';
        _completeOnce(_stdoutDone);
      },
    );
    _stderr = session.stderr.listen(
      _batcher.add,
      onDone: () => _completeOnce(_stderrDone),
      onError: (_, __) {
        _errorCode ??= 'member_output_error';
        _completeOnce(_stderrDone);
      },
    );
    unawaited(_finishWhenDone());
  }

  void write(Uint8List data) {
    if (!_closeRequested && !_finished.isCompleted) session.write(data);
  }

  void resize(int rows, int columns) {
    if (!_closeRequested && !_finished.isCompleted) {
      session.resize(rows, columns);
    }
  }

  void acknowledge(int sequence) {
    if (!_outstanding.remove(sequence) || !_paused) return;
    if (_eof && _outstanding.isEmpty) {
      _draining = true;
    }
    _resume();
  }

  Future<void> close() {
    if (!_closeRequested) {
      _closeRequested = true;
      session.close();
    }
    return done;
  }

  void _emit(Uint8List bytes) {
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
    if (!_draining && _outstanding.length >= outputWindow) _pause();
  }

  void _pause() {
    if (_paused) return;
    _paused = true;
    _stdout.pause();
    _stderr.pause();
    _batches.pause();
  }

  void _resume() {
    if (!_paused) return;
    _paused = false;
    _stdout.resume();
    _stderr.resume();
    _batches.resume();
  }

  Future<void> _finishWhenDone() async {
    try {
      try {
        await session.done;
      } on Object {
        // A local close can race dartssh2 channel completion. Output already
        // queued on the streams remains authoritative and is drained below.
        if (!_closeRequested) _errorCode ??= 'member_transport_error';
      }
      _eof = true;
      if (_closeRequested || _outstanding.isEmpty) {
        _draining = true;
        _resume();
      }
      await Future.wait([_stdoutDone.future, _stderrDone.future]);
      await _batcher.close();
      await _batches.cancel();
      sendEvent(
        SshWorkerEvent.outputChunk(
          streamId: id,
          sequence: _sequence,
          bytes: Uint8List(0),
          isFinal: true,
          exitCode: session.exitCode ?? 0,
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
}
