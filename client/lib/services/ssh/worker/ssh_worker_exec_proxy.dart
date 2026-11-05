import 'dart:async';
import 'dart:typed_data';

import 'ssh_worker_protocol.dart';

abstract interface class SshWorkerExecChannel {
  Stream<Uint8List> get stdout;
  Stream<Uint8List> get stderr;
  Future<int> get done;
  void write(Uint8List data);
  void closeStdin();
  void kill();
  void close();
}

/// A worker member failure without exposing worker-local transport details.
final class SshWorkerMemberException implements SshWorkerCodedException {
  const SshWorkerMemberException(this.code);

  @override
  final String code;

  @override
  String toString() => 'SshWorkerMemberException($code)';
}

final class SshWorkerExecProxy implements SshWorkerExecChannel {
  SshWorkerExecProxy({
    required this.id,
    required this.acknowledgeRemote,
    required this.writeRemote,
    required this.closeStdinRemote,
    required this.killRemote,
    required this.closeRemote,
    required this.onFinished,
  });

  final String id;
  final Future<void> Function(int sequence) acknowledgeRemote;
  final Future<void> Function(Uint8List data) writeRemote;
  final Future<void> Function() closeStdinRemote;
  final Future<void> Function() killRemote;
  final Future<void> Function() closeRemote;
  final void Function() onFinished;
  final StreamController<Uint8List> _stdout = StreamController<Uint8List>(
    sync: true,
  );
  final StreamController<Uint8List> _stderr = StreamController<Uint8List>(
    sync: true,
  );
  final Completer<int> _done = Completer<int>();
  var _nextSequence = 0;
  var _killRequested = false;
  var _closeRequested = false;
  var _finished = false;
  Future<void> _writeChain = Future<void>.value();

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  Future<int> get done => _done.future;

  @override
  void write(Uint8List data) {
    if (_finished || _killRequested || _closeRequested) return;
    _writeChain = _writeChain.then((_) => _writeChunks(data)).catchError((
      Object error,
    ) {
      finishError(error);
    });
  }

  @override
  void closeStdin() {
    if (_finished || _killRequested || _closeRequested) return;
    _writeChain = _writeChain
        .then((_) async {
          if (_finished) return;
          await closeStdinRemote();
        })
        .catchError((Object _) {
          // EOF is best effort; the session may already be closing.
        });
  }

  @override
  void kill() {
    if (_killRequested || _finished) return;
    _killRequested = true;
    unawaited(_killRemoteQuietly());
  }

  @override
  void close() {
    if (_closeRequested || _finished) return;
    _closeRequested = true;
    unawaited(_closeRemote());
  }

  void accept(SshWorkerEvent event) {
    if (_finished) return;
    if (event.sequence != _nextSequence) {
      finishError(const SshWorkerMemberException('exec_output_sequence'));
      return;
    }
    _nextSequence++;
    final bytes = event.bytes!;
    if (!event.isFinal!) {
      final output = event.stream == SshWorkerExecStream.stdout
          ? _stdout
          : _stderr;
      output.add(bytes);
      unawaited(_acknowledgeQuietly(event.sequence!));
      return;
    }
    final errorCode = event.errorCode;
    if (errorCode != null) {
      finishError(SshWorkerMemberException(errorCode));
      return;
    }
    finish(event.exitCode ?? -1);
  }

  void finish(int exitCode) {
    if (_finished) return;
    _finished = true;
    _closeRequested = true;
    _done.complete(exitCode);
    unawaited(_stdout.close());
    unawaited(_stderr.close());
    onFinished();
  }

  void finishError(Object error) {
    if (_finished) return;
    _finished = true;
    _closeRequested = true;
    _done.completeError(error);
    unawaited(_stdout.close());
    unawaited(_stderr.close());
    onFinished();
  }

  Future<void> _writeChunks(Uint8List data) async {
    for (
      var offset = 0;
      offset < data.length && !_finished;
      offset += sshWorkerMaxChunkSize
    ) {
      final end = (offset + sshWorkerMaxChunkSize).clamp(0, data.length);
      await writeRemote(Uint8List.sublistView(data, offset, end));
    }
  }

  Future<void> _killRemoteQuietly() async {
    try {
      await killRemote();
    } on Object catch (error) {
      finishError(error);
    }
  }

  Future<void> _acknowledgeQuietly(int sequence) async {
    try {
      await acknowledgeRemote(sequence);
    } on Object {
      // ACKs only provide flow control; a closing worker already terminates
      // the proxy through its transport lifecycle.
    }
  }

  Future<void> _closeRemote() async {
    try {
      await closeRemote();
    } on Object catch (error) {
      finishError(error);
    }
  }
}
