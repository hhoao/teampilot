import 'dart:async';
import 'dart:typed_data';

import '../../../models/ssh_profile.dart';
import '../ssh_storage_io.dart';
import 'ssh_profile_worker_manager.dart';
import 'ssh_worker_protocol.dart';
import 'ssh_worker_storage_types.dart';

abstract interface class SshWorkerStorageTransport {
  Future<void> connect(
    SshProfile profile,
    SshWorkerDialTarget target, {
    Duration timeout = const Duration(seconds: 30),
  });
  Future<SshWorkerRunResult> run(
    String command, {
    bool stderr = true,
    Uint8List? stdin,
    Duration timeout = const Duration(seconds: 30),
  });
  Future<String> openRead(
    String path, {
    required int chunkSize,
    required int window,
    int offset = 0,
    Duration? timeout,
  });
  Future<SshWorkerFileChunk?> readChunk(
    String streamId, {
    required int sequence,
    int? ackSequence,
    Duration? timeout,
  });
  Future<void> acknowledgeReadChunk(
    String streamId,
    int sequence, {
    Duration? timeout,
  });
  Future<String> openWrite(
    String path, {
    required int chunkSize,
    required bool append,
    Duration? timeout,
  });
  Future<void> writeChunk(
    String streamId,
    SshWorkerFileChunk chunk, {
    Duration? timeout,
  });
  Future<void> closeStream(String streamId, {Duration? timeout});
  Future<void> cancelStream(String streamId, {Duration? timeout});
  Future<SshWorkerFileStat> stat(String path, {Duration? timeout});
  Future<List<SshWorkerDirectoryEntry>> listDirectory(
    String path, {
    Duration? timeout,
  });
  Future<String> readlink(String path, {Duration? timeout});
  Future<String> realpath(String path, {Duration? timeout});
  Future<void> mkdir(String path, {Duration? timeout});
  Future<void> remove(String path, {bool directory = false, Duration? timeout});
}

typedef SshWorkerRequestSender =
    Future<SshWorkerReply> Function(SshWorkerRequest request);

const _sshWorkerStorageCleanupTimeout = Duration(seconds: 5);

final class SshWorkerLeaseStorageTransport
    implements SshWorkerStorageTransport {
  factory SshWorkerLeaseStorageTransport(
    SshProfileWorkerLease lease, {
    Duration requestTimeout = SshStorageIo.ioTimeout,
    Duration cleanupTimeout = _sshWorkerStorageCleanupTimeout,
    void Function()? onTimeout,
  }) => SshWorkerLeaseStorageTransport._(
    lease.send,
    requestTimeout: requestTimeout,
    cleanupTimeout: cleanupTimeout,
    onTimeout: onTimeout,
  );

  SshWorkerLeaseStorageTransport.forTesting(
    SshWorkerRequestSender send, {
    Duration requestTimeout = SshStorageIo.ioTimeout,
    Duration cleanupTimeout = _sshWorkerStorageCleanupTimeout,
    void Function()? onTimeout,
  }) : this._(
         send,
         requestTimeout: requestTimeout,
         cleanupTimeout: cleanupTimeout,
         onTimeout: onTimeout,
       );

  SshWorkerLeaseStorageTransport._(
    this._send, {
    required this.requestTimeout,
    required this.cleanupTimeout,
    this.onTimeout,
  });

  final SshWorkerRequestSender _send;
  final Duration requestTimeout;
  final Duration cleanupTimeout;
  final void Function()? onTimeout;
  var _requestSequence = 0;
  var _streamSequence = 0;

  @override
  Future<String> openRead(
    String path, {
    required int chunkSize,
    required int window,
    int offset = 0,
    Duration? timeout,
  }) async {
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    final streamId = _newStreamId('read');
    try {
      final reply = await _request(
        SshWorkerOperation.openSftpRead,
        {
          'streamId': streamId,
          'path': path,
          'chunkSize': chunkSize,
          'window': window,
          if (offset > 0) 'offset': offset,
        },
        timeout: timeout,
        streamIdForCancellation: streamId,
      );
      return _streamResult(reply, streamId);
    } on Object catch (error, stackTrace) {
      if (!_isTransportTimeout(error)) {
        await _bestEffortCancel(streamId, timeout: timeout);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<SshWorkerFileChunk?> readChunk(
    String streamId, {
    required int sequence,
    int? ackSequence,
    Duration? timeout,
  }) async {
    final reply = await _request(
      SshWorkerOperation.readSftpChunk,
      {
        'streamId': streamId,
        'sequence': sequence,
        if (ackSequence != null) 'ackSequence': ackSequence,
      },
      timeout: timeout,
      streamIdForCancellation: streamId,
    );
    return SshWorkerFileChunk.fromWire(reply.result);
  }

  @override
  Future<void> acknowledgeReadChunk(
    String streamId,
    int sequence, {
    Duration? timeout,
  }) => _request(
    SshWorkerOperation.acknowledgeSftpChunk,
    {'streamId': streamId, 'sequence': sequence},
    timeout: timeout,
    streamIdForCancellation: streamId,
  ).then((_) {});

  @override
  Future<String> openWrite(
    String path, {
    required int chunkSize,
    required bool append,
    Duration? timeout,
  }) async {
    final streamId = _newStreamId('write');
    try {
      final reply = await _request(
        SshWorkerOperation.openSftpWrite,
        {
          'streamId': streamId,
          'path': path,
          'chunkSize': chunkSize,
          'append': append,
        },
        timeout: timeout,
        streamIdForCancellation: streamId,
      );
      return _streamResult(reply, streamId);
    } on Object catch (error, stackTrace) {
      if (!_isTransportTimeout(error)) {
        await _bestEffortCancel(streamId, timeout: timeout);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<void> writeChunk(
    String streamId,
    SshWorkerFileChunk chunk, {
    Duration? timeout,
  }) => _request(
    SshWorkerOperation.writeSftpChunk,
    {'streamId': streamId, 'sequence': chunk.sequence, 'offset': chunk.offset},
    payload: chunk.bytes,
    timeout: timeout,
    streamIdForCancellation: streamId,
  ).then((_) {});

  @override
  Future<void> closeStream(String streamId, {Duration? timeout}) =>
      _finish(SshWorkerOperation.closeSftpStream, streamId, timeout: timeout);

  @override
  Future<void> cancelStream(String streamId, {Duration? timeout}) =>
      _finish(SshWorkerOperation.cancelRequest, streamId, timeout: timeout);

  @override
  Future<void> connect(
    SshProfile profile,
    SshWorkerDialTarget target, {
    Duration? timeout,
  }) => _request(SshWorkerOperation.connectStorage, {
    'profile': profile.toJson(),
    'target': target.toWire(),
  }, timeout: timeout).then((_) {});

  @override
  Future<SshWorkerRunResult> run(
    String command, {
    bool stderr = true,
    Uint8List? stdin,
    Duration? timeout,
  }) async => SshWorkerRunResult.fromWire(
    (await _request(
      SshWorkerOperation.runStorage,
      {'command': command, 'stderr': stderr},
      payload: stdin,
      timeout: timeout,
    )).result,
    maxOutputBytes: sshWorkerMaxStorageExecOutput,
  );

  @override
  Future<SshWorkerFileStat> stat(String path, {Duration? timeout}) async =>
      SshWorkerFileStat.fromWire(
        (await _request(SshWorkerOperation.statSftp, {
          'path': path,
        }, timeout: timeout)).result,
      );

  @override
  Future<List<SshWorkerDirectoryEntry>> listDirectory(
    String path, {
    Duration? timeout,
  }) async {
    final entries = (await _request(SshWorkerOperation.listSftpDirectory, {
      'path': path,
    }, timeout: timeout)).result['entries'];
    if (entries is! List) {
      throw const FormatException('Invalid directory result');
    }
    return [
      for (final entry in entries) SshWorkerDirectoryEntry.fromWire(entry),
    ];
  }

  @override
  Future<String> readlink(String path, {Duration? timeout}) =>
      _pathResult(SshWorkerOperation.readlinkSftp, path, timeout: timeout);

  @override
  Future<String> realpath(String path, {Duration? timeout}) =>
      _pathResult(SshWorkerOperation.realpathSftp, path, timeout: timeout);

  @override
  Future<void> mkdir(String path, {Duration? timeout}) => _request(
    SshWorkerOperation.mkdirSftp,
    {'path': path},
    timeout: timeout,
  ).then((_) {});

  @override
  Future<void> remove(
    String path, {
    bool directory = false,
    Duration? timeout,
  }) => _request(SshWorkerOperation.removeSftp, {
    'path': path,
    'directory': directory,
  }, timeout: timeout).then((_) {});

  Future<String> _pathResult(
    SshWorkerOperation operation,
    String path, {
    Duration? timeout,
  }) async {
    final value = (await _request(operation, {
      'path': path,
    }, timeout: timeout)).result['path'];
    if (value is! String) {
      throw const FormatException('Invalid storage path result');
    }
    return value;
  }

  Future<void> _finish(
    SshWorkerOperation operation,
    String streamId, {
    Duration? timeout,
  }) => _request(operation, {
    'streamId': streamId,
  }, timeout: timeout).then((_) {});

  Future<void> _bestEffortCancel(String streamId, {Duration? timeout}) async {
    final effectiveTimeout = timeout ?? requestTimeout;
    final cleanupTimeout = effectiveTimeout < this.cleanupTimeout
        ? effectiveTimeout
        : this.cleanupTimeout;
    final request = SshWorkerRequest(
      requestId: 'storage-${_requestSequence++}',
      operation: SshWorkerOperation.cancelRequest,
      args: {'streamId': streamId, 'timeoutMs': cleanupTimeout.inMilliseconds},
    );
    try {
      final reply = await _send(request).timeout(cleanupTimeout);
      if (reply.kind != SshWorkerReplyKind.success) return;
    } on Object {
      // The open request may have failed because the worker is already gone.
    }
  }

  String _newStreamId(String kind) => '$kind-${_streamSequence++}';

  String _streamResult(SshWorkerReply reply, String expected) {
    final streamId = reply.result['streamId'];
    if (streamId is! String || streamId != expected) {
      throw const FormatException('Invalid storage stream result');
    }
    return streamId;
  }

  Future<SshWorkerReply> _request(
    SshWorkerOperation operation,
    Map<String, Object?> args, {
    Uint8List? payload,
    Duration? timeout,
    String? streamIdForCancellation,
  }) async {
    final effectiveTimeout = timeout ?? requestTimeout;
    final request = SshWorkerRequest(
      requestId: 'storage-${_requestSequence++}',
      operation: operation,
      args: {...args, 'timeoutMs': effectiveTimeout.inMilliseconds},
      payload: payload,
    );
    final SshWorkerReply reply;
    try {
      reply = await _send(request).timeout(effectiveTimeout);
    } on TimeoutException catch (_, stackTrace) {
      onTimeout?.call();
      if (streamIdForCancellation != null) {
        await _bestEffortCancel(
          streamIdForCancellation,
          timeout: effectiveTimeout,
        );
      }
      Error.throwWithStackTrace(
        const SshWorkerTransportException(
          'Worker storage request timed out',
          code: 'transport_timeout',
        ),
        stackTrace,
      );
    }
    if (reply.kind != SshWorkerReplyKind.success) {
      final error = SshWorkerTransportException(
        reply.error?.message ?? 'Worker storage operation failed',
        code: reply.kind == SshWorkerReplyKind.cancellation
            ? 'cancelled'
            : reply.error?.code,
      );
      if (error.code == 'transport_timeout') {
        onTimeout?.call();
        if (streamIdForCancellation != null) {
          await _bestEffortCancel(
            streamIdForCancellation,
            timeout: effectiveTimeout,
          );
        }
      }
      throw error;
    }
    return reply;
  }

  bool _isTransportTimeout(Object error) =>
      error is SshWorkerTransportException && error.code == 'transport_timeout';
}

/// Narrow storage surface consumed outside the SSH worker implementation.
abstract interface class SshWorkerStorageFacade {
  Future<SshWorkerFileStat> stat(
    String path, {
    Duration timeout = SshStorageIo.ioTimeout,
  });
  Future<List<SshWorkerDirectoryEntry>> listDirectory(
    String path, {
    Duration timeout = SshStorageIo.ioTimeout,
  });
  Future<String> readlink(
    String path, {
    Duration timeout = SshStorageIo.ioTimeout,
  });
  Future<String> realpath(
    String path, {
    Duration timeout = SshStorageIo.ioTimeout,
  });
  Future<void> mkdir(String path, {Duration timeout = SshStorageIo.ioTimeout});
  Future<void> remove(
    String path, {
    bool directory = false,
    Duration timeout = SshStorageIo.ioTimeout,
  });
  Future<Uint8List> readBytes(
    String path, {
    int offset = 0,
    int? length,
    Duration timeout = SshStorageIo.ioTimeout,
  });
  Future<void> writeBytes(
    String path,
    Uint8List bytes, {
    bool append = false,
    Duration timeout = SshStorageIo.ioTimeout,
  });
}

final class SshWorkerStorageClient implements SshWorkerStorageFacade {
  SshWorkerStorageClient(
    this._transport, {
    this.chunkSize = 256 * 1024,
    this.writeChunkSize = sshWorkerMaxChunkSize,
    this.maxInFlightChunks = 8,
    this.cleanupTimeout = _sshWorkerStorageCleanupTimeout,
    this.requestTimeout = SshStorageIo.ioTimeout,
  }) {
    if (chunkSize < 1 || chunkSize > sshWorkerMaxChunkSize) {
      throw ArgumentError.value(chunkSize, 'chunkSize');
    }
    if (writeChunkSize < 1 || writeChunkSize > sshWorkerMaxChunkSize) {
      throw ArgumentError.value(writeChunkSize, 'writeChunkSize');
    }
    if (maxInFlightChunks < 1 || maxInFlightChunks > sshWorkerMaxReadWindow) {
      throw ArgumentError.value(maxInFlightChunks, 'maxInFlightChunks');
    }
  }

  final SshWorkerStorageTransport _transport;
  final int chunkSize;
  final int writeChunkSize;
  final int maxInFlightChunks;
  final Duration cleanupTimeout;
  final Duration requestTimeout;

  Duration _timeout(Duration? timeout) => timeout ?? requestTimeout;

  Future<void> connect(
    SshProfile profile,
    SshWorkerDialTarget target, {
    Duration timeout = SshStorageIo.ioTimeout,
  }) => _transport.connect(profile, target, timeout: _timeout(timeout));

  Future<SshWorkerRunResult> run(
    String command, {
    bool stderr = true,
    Uint8List? stdin,
    Duration timeout = SshStorageIo.ioTimeout,
  }) => _transport.run(
    command,
    stderr: stderr,
    stdin: stdin,
    timeout: _timeout(timeout),
  );

  @override
  Future<SshWorkerFileStat> stat(
    String path, {
    Duration timeout = SshStorageIo.ioTimeout,
  }) => _transport.stat(path, timeout: _timeout(timeout));

  @override
  Future<List<SshWorkerDirectoryEntry>> listDirectory(
    String path, {
    Duration timeout = SshStorageIo.ioTimeout,
  }) => _transport.listDirectory(path, timeout: _timeout(timeout));

  @override
  Future<String> readlink(
    String path, {
    Duration timeout = SshStorageIo.ioTimeout,
  }) => _transport.readlink(path, timeout: _timeout(timeout));

  @override
  Future<String> realpath(
    String path, {
    Duration timeout = SshStorageIo.ioTimeout,
  }) => _transport.realpath(path, timeout: _timeout(timeout));

  @override
  Future<void> mkdir(
    String path, {
    Duration timeout = SshStorageIo.ioTimeout,
  }) => _transport.mkdir(path, timeout: _timeout(timeout));

  @override
  Future<void> remove(
    String path, {
    bool directory = false,
    Duration timeout = SshStorageIo.ioTimeout,
  }) =>
      _transport.remove(path, directory: directory, timeout: _timeout(timeout));

  @override
  Future<Uint8List> readBytes(
    String path, {
    int offset = 0,
    int? length,
    Duration timeout = SshStorageIo.ioTimeout,
  }) async {
    if (offset < 0 || (length != null && length < 0)) {
      throw ArgumentError('Read offset and length must be non-negative');
    }
    if (length == 0) return Uint8List(0);
    final bytes = BytesBuilder(copy: false);
    const stopped = _SshWorkerReadComplete();
    try {
      await readChunks(
        path,
        offset: offset,
        timeout: _timeout(timeout),
        onChunk: (chunk) async {
          final chunkStart = chunk.offset;
          final chunkEnd = chunkStart + chunk.bytes.length;
          final requestedEnd = length == null ? null : offset + length;
          if (chunkEnd > offset &&
              (requestedEnd == null || chunkStart < requestedEnd)) {
            final start = offset > chunkStart ? offset - chunkStart : 0;
            final end = requestedEnd != null && requestedEnd < chunkEnd
                ? requestedEnd - chunkStart
                : chunk.bytes.length;
            if (end > start) {
              bytes.add(
                start == 0 && end == chunk.bytes.length
                    ? chunk.bytes
                    : chunk.bytes.sublist(start, end),
              );
            }
          }
          if (requestedEnd != null && chunkEnd >= requestedEnd) throw stopped;
        },
      );
    } on _SshWorkerReadComplete {
      // Reaching the requested range deliberately cancels the remaining stream.
    }
    return bytes.takeBytes();
  }

  @override
  Future<void> writeBytes(
    String path,
    Uint8List bytes, {
    bool append = false,
    Duration timeout = SshStorageIo.ioTimeout,
  }) => writeChunks(
    path,
    () async* {
      for (var offset = 0; offset < bytes.length; offset += writeChunkSize) {
        final end = (offset + writeChunkSize).clamp(0, bytes.length);
        yield Uint8List.sublistView(bytes, offset, end);
      }
    }(),
    append: append,
    timeout: _timeout(timeout),
  );

  Future<void> readChunks(
    String path, {
    required Future<void> Function(SshWorkerFileChunk chunk) onChunk,
    int offset = 0,
    Duration timeout = SshStorageIo.ioTimeout,
  }) async {
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    final operationTimeout = _timeout(timeout);
    String? streamId;
    var completed = false;
    try {
      streamId = await _transport.openRead(
        path,
        chunkSize: chunkSize,
        window: maxInFlightChunks,
        offset: offset,
        timeout: operationTimeout,
      );
      var nextSequence = 0;
      var nextToConsume = 0;
      var done = false;
      int? pendingAck;
      // Keep the protocol window full: each consumed chunk frees one slot and
      // piggybacks its acknowledgement on the next read request. This avoids a
      // separate ACK round trip per 64 KiB chunk.
      final inFlight = <int, Future<Object?>>{};

      Future<void> fillWindow() async {
        while (!done && inFlight.length < maxInFlightChunks) {
          final sequence = nextSequence++;
          final ack = pendingAck;
          pendingAck = null;
          inFlight[sequence] = _transport
              .readChunk(
                streamId!,
                sequence: sequence,
                ackSequence: ack,
                timeout: operationTimeout,
              )
              .then<Object?>(
                (chunk) => chunk,
                onError: (Object error, StackTrace stackTrace) =>
                    _ReadFailure(error, stackTrace),
              );
        }
      }

      await fillWindow();
      while (!done) {
        final future = inFlight.remove(nextToConsume);
        if (future == null) break;
        final result = await future;
        if (result is _ReadFailure) {
          Error.throwWithStackTrace(result.error, result.stackTrace);
        }
        final chunk = result as SshWorkerFileChunk?;
        if (chunk == null) {
          done = true;
          break;
        }
        await onChunk(chunk);
        nextToConsume++;
        if (chunk.isFinal || chunk.bytes.length < chunkSize) {
          done = true;
          break;
        }
        pendingAck = chunk.sequence;
        await fillWindow();
      }
      completed = true;
    } finally {
      final activeStream = streamId;
      if (activeStream != null) {
        if (completed) {
          await _bestEffortCleanup(
            () =>
                _transport.closeStream(activeStream, timeout: operationTimeout),
            timeout: operationTimeout,
          );
        } else {
          await _bestEffortCleanup(
            () => _transport.cancelStream(
              activeStream,
              timeout: operationTimeout,
            ),
            timeout: operationTimeout,
          );
        }
      }
    }
  }

  Future<void> writeChunks(
    String path,
    Stream<Uint8List> chunks, {
    bool append = false,
    Duration timeout = SshStorageIo.ioTimeout,
  }) async {
    final operationTimeout = _timeout(timeout);
    String? streamId;
    var completed = false;
    try {
      streamId = await _transport.openWrite(
        path,
        chunkSize: writeChunkSize,
        append: append,
        timeout: operationTimeout,
      );
      var sequence = 0;
      var offset = 0;
      await for (final bytes in chunks) {
        for (var start = 0; start < bytes.length; start += writeChunkSize) {
          final end = (start + writeChunkSize).clamp(0, bytes.length);
          final chunkBytes = Uint8List.sublistView(bytes, start, end);
          final chunk = SshWorkerFileChunk(
            sequence: sequence,
            offset: offset,
            bytes: chunkBytes,
          );
          try {
            await _transport.writeChunk(
              streamId,
              chunk,
              timeout: operationTimeout,
            );
          } on SshWorkerTransportException {
            rethrow;
          } on Object catch (error) {
            throw SshWorkerTransportException(
              '$error',
              code: 'transport_error',
            );
          }
          sequence++;
          offset += chunkBytes.length;
        }
      }
      completed = true;
    } finally {
      final activeStream = streamId;
      if (activeStream != null) {
        if (completed) {
          await _bestEffortCleanup(
            () =>
                _transport.closeStream(activeStream, timeout: operationTimeout),
            timeout: operationTimeout,
          );
        } else {
          await _bestEffortCleanup(
            () => _transport.cancelStream(
              activeStream,
              timeout: operationTimeout,
            ),
            timeout: operationTimeout,
          );
        }
      }
    }
  }

  Future<void> _bestEffortCleanup(
    Future<void> Function() cleanup, {
    required Duration timeout,
  }) async {
    try {
      final boundedTimeout = timeout < cleanupTimeout
          ? timeout
          : cleanupTimeout;
      await cleanup().timeout(boundedTimeout);
    } on Object {
      // Preserve the transfer or consumer error; cleanup is best effort.
    }
  }
}

final class _SshWorkerReadComplete implements Exception {
  const _SshWorkerReadComplete();
}

/// Captures a pipelined read error without leaking it as an unhandled future
/// while an earlier sequence is still being consumed.
final class _ReadFailure {
  const _ReadFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}
