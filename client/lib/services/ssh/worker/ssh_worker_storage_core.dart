import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

import '../ssh_storage_io.dart';
import '../ssh_transport_close.dart';
import 'ssh_worker_errors.dart';
import 'ssh_worker_protocol.dart';
import 'ssh_worker_storage_backend.dart';
import 'ssh_worker_storage_types.dart';

/// Worker-side storage request actor, with bounded outstanding read credits.
/// Every reserved credit survives delivery until the consumer acknowledges it.
final class SshWorkerStorageCore {
  SshWorkerStorageCore({required this.backend, required this.sendEvent});

  final SshWorkerStorageBackend backend;
  final void Function(SshWorkerEvent event) sendEvent;
  final Map<String, _StorageStream> _streams = {};
  Future<void>? _connecting;
  var _connected = false;
  var _stopped = false;
  var _epoch = 0;
  final _invalidations = StreamController<void>.broadcast(sync: true);

  Future<SshWorkerReply> handle(SshWorkerRequest request) async {
    final invalidation = Completer<Map<String, Object?>>();
    final invalidationSubscription = _invalidations.stream.listen((_) {
      if (!invalidation.isCompleted) {
        invalidation.completeError(_failure('transport_closed'));
      }
    });
    try {
      if (_stopped) throw _failure('worker_shutting_down');
      final timeout = Duration(
        milliseconds: _integer(
          request,
          'timeoutMs',
          defaultValue: SshStorageIo.ioTimeout.inMilliseconds,
          min: 1,
        ),
      );
      final result = await Future.any([
        _dispatch(request, timeout),
        invalidation.future,
      ]).timeout(timeout);
      return SshWorkerReply.success(request.requestId, result: result);
    } on TimeoutException {
      invalidate(SshTransportCloseReason.transportError);
      return _error(request, 'transport_timeout');
    } on SftpStatusError catch (error) {
      return _error(
        request,
        error.code == SftpStatusCode.noSuchFile
            ? 'sftp_no_such_file'
            : 'sftp_error',
      );
    } on SshWorkerTransportException catch (error) {
      if (error.code == 'cancelled')
        return SshWorkerReply.cancellation(request.requestId);
      return _error(request, error.code ?? 'transport_error');
    } on ArgumentError {
      return _error(request, 'invalid_storage_request');
    } on FormatException {
      return _error(request, 'invalid_storage_request');
    } on Object catch (error) {
      invalidate(SshTransportCloseReason.transportError);
      return _error(request, sshWorkerErrorCode(error));
    } finally {
      await invalidationSubscription.cancel();
      if (!invalidation.isCompleted) {
        // Release the Future.any listener without surfacing a late error.
        invalidation.complete(const {});
      }
    }
  }

  Future<Map<String, Object?>> _dispatch(
    SshWorkerRequest request,
    Duration timeout,
  ) async {
    final operation = request.operation;
    if (operation == SshWorkerOperation.connectStorage) {
      if (!_connected) {
        await (_connecting ??= _connect(request));
      }
      return const {};
    }
    if (operation == SshWorkerOperation.closeSftpStream ||
        operation == SshWorkerOperation.cancelRequest) {
      await _closeStream(_string(request, 'streamId'));
      return const {};
    }
    if (!_connected) throw _failure('storage_not_connected');
    switch (operation) {
      case SshWorkerOperation.runStorage:
        return (await backend.run(
          _string(request, 'command'),
          stderr: _boolean(request, 'stderr', defaultValue: true),
          stdin: request.payload,
        )).toWire(maxOutputBytes: sshWorkerMaxStorageExecOutput);
      case SshWorkerOperation.statSftp:
      case SshWorkerOperation.listSftpDirectory:
      case SshWorkerOperation.readlinkSftp:
      case SshWorkerOperation.realpathSftp:
      case SshWorkerOperation.mkdirSftp:
      case SshWorkerOperation.removeSftp:
        return backend.metadata(
          operation,
          _string(request, 'path'),
          directory: _boolean(request, 'directory', defaultValue: false),
        );
      case SshWorkerOperation.openSftpRead:
      case SshWorkerOperation.openSftpWrite:
        return _open(request, timeout);
      case SshWorkerOperation.readSftpChunk:
        return _read(request);
      case SshWorkerOperation.acknowledgeSftpChunk:
        final state = _stream(request, write: false);
        final sequence = _integer(request, 'sequence');
        if (!state.delivered.remove(sequence)) throw _failure('invalid_ack');
        state.outstanding.remove(sequence);
        _armIdle(state);
        return const {};
      case SshWorkerOperation.writeSftpChunk:
        return _write(request);
      default:
        throw _failure('unsupported_operation');
    }
  }

  Future<void> _connect(SshWorkerRequest request) async {
    final epoch = _epoch;
    sendEvent(
      SshWorkerEvent.stateChanged(
        state: SshWorkerState.connecting,
        plane: SshTransportPlane.storage,
      ),
    );
    try {
      await backend.connect(request);
      if (epoch != _epoch || _stopped) throw _failure('transport_closed');
      _connected = true;
      sendEvent(
        SshWorkerEvent.stateChanged(
          state: SshWorkerState.connected,
          plane: SshTransportPlane.storage,
        ),
      );
    } on Object {
      if (epoch == _epoch) invalidate(SshTransportCloseReason.transportError);
      rethrow;
    } finally {
      if (epoch == _epoch) _connecting = null;
    }
  }

  Future<Map<String, Object?>> _open(
    SshWorkerRequest request,
    Duration timeout,
  ) async {
    final id = _string(request, 'streamId');
    if (_streams.containsKey(id)) throw _failure('stream_exists');
    final path = _string(request, 'path');
    final write = request.operation == SshWorkerOperation.openSftpWrite;
    final chunkSize = _integer(
      request,
      'chunkSize',
      defaultValue: 64 * 1024,
      min: 1,
      max: sshWorkerMaxChunkSize,
    );
    final window = _integer(
      request,
      'window',
      defaultValue: 4,
      min: 1,
      max: sshWorkerMaxReadWindow,
    );
    final append = _boolean(request, 'append', defaultValue: false);
    final offset = write
        ? 0
        : _integer(request, 'offset', defaultValue: 0, min: 0);
    final state = _StorageStream(
      id,
      write,
      chunkSize,
      window,
      timeout,
      baseOffset: offset,
    );
    _streams[id] = state;
    _armIdle(state);
    // Register before awaiting open so cancellation also owns late handles.
    final opened = backend.open(path, write: write, append: append).then((
      file,
    ) async {
      if (state.closed.isCompleted) {
        await _bestEffortCloseFile(file, timeout);
        throw _failure('cancelled');
      }
      state.file = file;
      return file;
    });
    try {
      await _untilClosed(state, opened);
      return {'streamId': id};
    } on Object catch (error, stackTrace) {
      await _bestEffortCloseStream(id, timeout);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<Map<String, Object?>> _read(SshWorkerRequest request) async {
    final state = _stream(request, write: false);
    final ackSequence = request.args['ackSequence'];
    if (ackSequence != null) {
      final ack = _integer(request, 'ackSequence');
      if (!state.delivered.remove(ack)) throw _failure('invalid_ack');
      state.outstanding.remove(ack);
      _armIdle(state);
    }
    final sequence = _integer(request, 'sequence');
    if (sequence != state.nextSequence) throw _failure('invalid_sequence');
    if (state.outstanding.length >= state.window)
      throw _failure('read_window_full');
    state.nextSequence++;
    state.outstanding.add(sequence);
    final offset = state.baseOffset + sequence * state.chunkSize;
    try {
      final bytes = await _untilClosed(
        state,
        state.file!.read(offset, state.chunkSize),
      );
      if (bytes.length > state.chunkSize) throw _failure('invalid_chunk');
      state.delivered.add(sequence);
      return SshWorkerFileChunk(
        sequence: sequence,
        offset: offset,
        bytes: bytes,
        isFinal: bytes.length < state.chunkSize,
      ).toWire();
    } on Object catch (error, stackTrace) {
      await _bestEffortCloseStream(state.id, state.timeout);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<Map<String, Object?>> _write(SshWorkerRequest request) async {
    final state = _stream(request, write: true);
    final sequence = _integer(request, 'sequence');
    final offset = _integer(request, 'offset');
    final bytes = request.payload;
    if (state.writing ||
        sequence != state.nextSequence ||
        offset != state.offset)
      throw _failure('invalid_sequence');
    if (bytes == null || bytes.length > state.chunkSize)
      throw _failure('invalid_chunk');
    state.writing = true;
    try {
      await _untilClosed(state, state.file!.write(bytes, offset));
      state.nextSequence++;
      state.offset += bytes.length;
      _armIdle(state);
      // Success is the server's SFTP WRITE acknowledgement, never enqueue time.
      return {'sequence': sequence, 'offset': state.offset};
    } on Object catch (error, stackTrace) {
      await _bestEffortCloseStream(state.id, state.timeout);
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      state.writing = false;
    }
  }

  _StorageStream _stream(SshWorkerRequest request, {required bool write}) {
    final state = _streams[_string(request, 'streamId')];
    if (state == null || state.closed.isCompleted)
      throw _failure('stream_closed');
    if (state.write != write || state.file == null)
      throw _failure('invalid_stream');
    return state;
  }

  Future<T> _untilClosed<T>(_StorageStream state, Future<T> operation) =>
      Future.any([
        operation,
        state.closed.future.then<T>((_) => throw _failure('cancelled')),
      ]);

  void _armIdle(_StorageStream state) {
    state.idle?.cancel();
    state.idle = Timer(state.timeout, () {
      // Expired consumer acknowledgements/idle writers cannot retain handles.
      unawaited(
        _closeStream(state.id).catchError((Object _) {
          invalidate(SshTransportCloseReason.transportError);
        }),
      );
    });
  }

  Future<void> _closeStream(String id) async {
    final state = _streams.remove(id);
    if (state == null) return;
    state.idle?.cancel();
    state.closed.complete();
    state.outstanding.clear();
    state.delivered.clear();
    await _bestEffortCloseFile(state.file, state.timeout);
  }

  Future<void> _bestEffortCloseStream(String id, Duration timeout) async {
    try {
      await _closeStream(id).timeout(timeout);
    } on Object {
      // Cleanup must never replace the operation's original error.
    }
  }

  Future<void> _bestEffortCloseFile(
    SshWorkerStorageFile? file,
    Duration timeout,
  ) async {
    if (file == null) return;
    try {
      await file.close().timeout(timeout);
    } on Object {
      // The transport teardown is already best-effort.
    }
  }

  /// Force close the transport first: waiting for remote CLOSE on a dead
  /// connection must never delay timeout replies or worker shutdown.
  void invalidate(SshTransportCloseReason reason, {bool notify = true}) {
    final hadStorage = _connected || _connecting != null || _streams.isNotEmpty;
    _epoch++;
    _connected = false;
    _connecting = null;
    final states = _streams.values.toList();
    _streams.clear();
    for (final state in states) {
      state.idle?.cancel();
      state.closed.complete();
      state.outstanding.clear();
      state.delivered.clear();
    }
    if (!_invalidations.isClosed) _invalidations.add(null);
    backend.close();
    for (final state in states) {
      // Backend teardown has already invalidated all remote handles.
      unawaited(
        state.file?.close().timeout(state.timeout).catchError((Object _) {}),
      );
    }
    if (hadStorage && notify) {
      sendEvent(
        SshWorkerEvent.transportClosed(
          plane: SshTransportPlane.storage,
          reason: reason,
        ),
      );
    }
  }

  void shutdown() {
    _stopped = true;
    invalidate(SshTransportCloseReason.disconnectAll, notify: false);
    if (!_invalidations.isClosed) unawaited(_invalidations.close());
  }

  int _integer(
    SshWorkerRequest request,
    String name, {
    int? defaultValue,
    int min = 0,
    int? max,
  }) {
    final value = request.args[name] ?? defaultValue;
    if (value is! int || value < min || (max != null && value > max))
      throw ArgumentError('Invalid $name');
    return value;
  }

  bool _boolean(
    SshWorkerRequest request,
    String name, {
    required bool defaultValue,
  }) {
    final value = request.args[name] ?? defaultValue;
    if (value is! bool) throw ArgumentError('Invalid $name');
    return value;
  }

  String _string(SshWorkerRequest request, String name) {
    final value = request.args[name];
    if (value is! String || value.isEmpty) throw ArgumentError('Missing $name');
    return value;
  }

  SshWorkerTransportException _failure(String code) =>
      SshWorkerTransportException(
        'Worker storage operation failed',
        code: code,
      );
  SshWorkerReply _error(SshWorkerRequest request, String code) =>
      SshWorkerReply.failure(
        request.requestId,
        SshWorkerErrorRecord(
          code: code,
          message: 'Worker storage operation failed',
        ),
      );
}

final class _StorageStream {
  _StorageStream(
    this.id,
    this.write,
    this.chunkSize,
    this.window,
    this.timeout, {
    this.baseOffset = 0,
  });
  final String id;
  final bool write;
  final int chunkSize;
  final int window;
  final Duration timeout;
  final int baseOffset;
  final closed = Completer<void>();
  final outstanding = <int>{};
  final delivered = <int>{};
  SshWorkerStorageFile? file;
  Timer? idle;
  var nextSequence = 0;
  var offset = 0;
  var writing = false;
}
