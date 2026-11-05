import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_protocol.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_client.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_types.dart';

void main() {
  test(
    'read stream never has more than the configured window in flight',
    () async {
      final transport = _FakeStorageTransport();
      final storage = SshWorkerStorageClient(
        transport,
        chunkSize: 1,
        maxInFlightChunks: 4,
      );

      final chunks = <Uint8List>[];
      await storage.readChunks(
        '/large.bin',
        onChunk: (chunk) async {
          chunks.add(chunk.bytes);
          await Future<void>.delayed(const Duration(milliseconds: 1));
        },
      );

      expect(transport.maxObservedUnacknowledgedChunks, 4);
      expect(transport.maxConcurrentReads, 4);
      expect(chunks, isNotEmpty);
      expect(transport.closedStreams, ['read-0']);
      expect(transport.cancelledStreams, isEmpty);
    },
  );

  test('read closes its worker stream after normal EOF', () async {
    final transport = _FakeStorageTransport(readChunkCount: 1);

    await SshWorkerStorageClient(
      transport,
      chunkSize: 1,
    ).readChunks('/file', onChunk: (_) async {});

    expect(transport.closedStreams, ['read-0']);
    expect(transport.cancelledStreams, isEmpty);
  });

  test('read cancels its worker stream when transport fails', () async {
    final transport = _FakeStorageTransport(failReadAtSequence: 0);

    await expectLater(
      SshWorkerStorageClient(
        transport,
        chunkSize: 1,
      ).readChunks('/file', onChunk: (_) async {}),
      throwsA(isA<SshWorkerTransportException>()),
    );

    expect(transport.closedStreams, isEmpty);
    expect(transport.cancelledStreams, ['read-0']);
  });

  test('read preserves its original error when cancellation fails', () async {
    final transport = _FakeStorageTransport(
      failReadAtSequence: 0,
      failCleanup: true,
    );

    await expectLater(
      SshWorkerStorageClient(
        transport,
        chunkSize: 1,
        cleanupTimeout: const Duration(milliseconds: 10),
      ).readChunks('/file', onChunk: (_) async {}),
      throwsA(
        predicate<Object>((error) => error.toString().contains('read failed')),
      ),
    );
  });

  test('write cleanup is bounded and preserves its original error', () async {
    final transport = _FakeStorageTransport(
      failWriteAtSequence: 0,
      hangCleanup: true,
    );

    await expectLater(
      SshWorkerStorageClient(
            transport,
            cleanupTimeout: const Duration(milliseconds: 10),
          )
          .writeChunks(
            '/file',
            Stream<Uint8List>.value(Uint8List.fromList([1])),
          )
          .timeout(const Duration(milliseconds: 100)),
      throwsA(
        predicate<Object>((error) => error.toString().contains('write failed')),
      ),
    );
  });

  test('read cancels its worker stream when the callback fails', () async {
    final transport = _FakeStorageTransport(readChunkCount: 1);

    await expectLater(
      SshWorkerStorageClient(transport, chunkSize: 1).readChunks(
        '/file',
        onChunk: (_) async => throw StateError('consumer stopped'),
      ),
      throwsStateError,
    );

    expect(transport.closedStreams, isEmpty);
    expect(transport.cancelledStreams, ['read-0']);
  });

  test('read cancellation cancels its worker stream', () async {
    final transport = _FakeStorageTransport(readChunkCount: 1);

    await expectLater(
      SshWorkerStorageClient(transport, chunkSize: 1).readChunks(
        '/file',
        onChunk: (_) async => throw const SshWorkerTransportException(
          'cancelled',
          code: 'cancelled',
        ),
      ),
      throwsA(isA<SshWorkerTransportException>()),
    );

    expect(transport.cancelledStreams, ['read-0']);
  });

  test('ranged reads stop through worker stream cancellation', () async {
    final transport = _FakeStorageTransport(readChunkCount: 5);

    final bytes = await SshWorkerStorageClient(
      transport,
      chunkSize: 1,
    ).readBytes('/file', offset: 1, length: 2);

    expect(bytes, [1, 2]);
    expect(transport.cancelledStreams, ['read-0']);
  });

  test('ranged reads open the worker stream at the requested offset', () async {
    final transport = _FakeStorageTransport(readChunkCount: 8);

    final bytes = await SshWorkerStorageClient(
      transport,
      chunkSize: 1,
    ).readBytes('/file', offset: 3, length: 1);

    expect(bytes, [3]);
    expect(transport.lastReadOffset, 3);
  });

  test('failed write cancels after the failed chunk and stops', () async {
    final transport = _FakeStorageTransport(failWriteAtSequence: 2);

    await expectLater(
      SshWorkerStorageClient(transport).writeChunks(
        '/file',
        Stream<Uint8List>.fromIterable([
          Uint8List.fromList([0]),
          Uint8List.fromList([1]),
          Uint8List.fromList([2]),
          Uint8List.fromList([3]),
        ]),
      ),
      throwsA(isA<SshWorkerTransportException>()),
    );

    expect(transport.acknowledgedSequences, [0, 1]);
    expect(transport.closedStreams, isEmpty);
    expect(transport.cancelledStreams, ['write-0']);
  });

  test(
    'successful write closes its worker stream, including an empty transfer',
    () async {
      final transport = _FakeStorageTransport();

      await SshWorkerStorageClient(transport).writeChunks(
        '/file',
        Stream<Uint8List>.fromIterable([
          Uint8List.fromList([1, 2]),
          Uint8List.fromList([3]),
        ]),
      );
      await SshWorkerStorageClient(
        transport,
      ).writeChunks('/file', const Stream<Uint8List>.empty());

      expect(transport.acknowledgedSequences, [0, 1]);
      expect(transport.closedStreams, ['write-0', 'write-1']);
      expect(transport.cancelledStreams, isEmpty);
    },
  );

  test(
    'large write inputs are split to the configured worker chunk size',
    () async {
      final transport = _FakeStorageTransport();

      await SshWorkerStorageClient(
        transport,
        writeChunkSize: 2,
      ).writeBytes('/file', Uint8List.fromList([0, 1, 2, 3, 4]));

      expect(transport.acknowledgedSequences, [0, 1, 2]);
      expect(transport.writtenChunkSizes, [2, 2, 1]);
    },
  );

  test(
    'lease transport gives repeated same-path transfers independent streams',
    () async {
      final requests = <SshWorkerRequest>[];
      final transport = SshWorkerLeaseStorageTransport.forTesting((
        request,
      ) async {
        requests.add(request);
        switch (request.operation) {
          case SshWorkerOperation.openSftpRead:
          case SshWorkerOperation.openSftpWrite:
            return SshWorkerReply.success(
              request.requestId,
              result: {'streamId': request.args['streamId']},
            );
          case SshWorkerOperation.readSftpChunk:
            return SshWorkerReply.success(
              request.requestId,
              result: SshWorkerFileChunk(
                sequence: request.args['sequence']! as int,
                offset: 0,
                bytes: Uint8List.fromList([0, 255, 1]),
                isFinal: true,
              ).toWire(),
            );
          case SshWorkerOperation.acknowledgeSftpChunk:
          case SshWorkerOperation.writeSftpChunk:
          case SshWorkerOperation.closeSftpStream:
          case SshWorkerOperation.cancelRequest:
            return SshWorkerReply.success(request.requestId);
          default:
            throw StateError('Unexpected operation: ${request.operation}');
        }
      });
      final storage = SshWorkerStorageClient(
        transport,
        chunkSize: 3,
        maxInFlightChunks: 1,
      );

      await storage.readChunks('/same', onChunk: (_) async {});
      await storage.readChunks('/same', onChunk: (_) async {});
      await storage.writeChunks(
        '/same',
        Stream<Uint8List>.value(Uint8List.fromList([9, 0, 255])),
      );
      await storage.writeChunks(
        '/same',
        Stream<Uint8List>.value(Uint8List.fromList([8])),
      );

      final opens = requests
          .where(
            (request) =>
                request.operation == SshWorkerOperation.openSftpRead ||
                request.operation == SshWorkerOperation.openSftpWrite,
          )
          .toList();
      final streamIds = opens
          .map((request) => request.args['streamId'])
          .toSet();
      expect(opens, hasLength(4));
      expect(streamIds, hasLength(4));
      expect(
        requests.where(
          (request) => request.operation == SshWorkerOperation.closeSftpStream,
        ),
        hasLength(4),
      );
      final write = requests.firstWhere(
        (request) => request.operation == SshWorkerOperation.writeSftpChunk,
      );
      expect(write.payload, [9, 0, 255]);
    },
  );

  test(
    'lease transport cancels a stream when its open reply is malformed',
    () async {
      final operations = <SshWorkerOperation>[];
      final transport = SshWorkerLeaseStorageTransport.forTesting((
        request,
      ) async {
        operations.add(request.operation);
        if (request.operation == SshWorkerOperation.openSftpRead) {
          return SshWorkerReply.success(request.requestId);
        }
        return SshWorkerReply.success(request.requestId);
      });

      await expectLater(
        transport.openRead('/file', chunkSize: 1, window: 1),
        throwsFormatException,
      );
      expect(operations, [
        SshWorkerOperation.openSftpRead,
        SshWorkerOperation.cancelRequest,
      ]);
    },
  );

  test('lease transport bounds a silently hung UI request', () async {
    final transport = SshWorkerLeaseStorageTransport.forTesting(
      (_) => Completer<SshWorkerReply>().future,
      requestTimeout: const Duration(milliseconds: 10),
    );

    await expectLater(
      transport.stat('/hung'),
      throwsA(
        isA<SshWorkerTransportException>().having(
          (error) => error.code,
          'code',
          'transport_timeout',
        ),
      ),
    );
  });

  test('caller exec timeout overrides the transport default', () async {
    final transport = SshWorkerLeaseStorageTransport.forTesting(
      (_) => Completer<SshWorkerReply>().future,
      requestTimeout: const Duration(seconds: 1),
    );

    await expectLater(
      transport.run('hung', timeout: const Duration(milliseconds: 10)),
      throwsA(
        isA<SshWorkerTransportException>().having(
          (error) => error.code,
          'code',
          'transport_timeout',
        ),
      ),
    );
  });

  test(
    'caller timeout propagates to open and cancels the worker stream',
    () async {
      final requests = <SshWorkerRequest>[];
      final transport = SshWorkerLeaseStorageTransport.forTesting((request) {
        requests.add(request);
        if (request.operation == SshWorkerOperation.openSftpRead) {
          return Completer<SshWorkerReply>().future;
        }
        return Future<SshWorkerReply>.value(
          SshWorkerReply.success(request.requestId),
        );
      });

      await expectLater(
        transport.openRead(
          '/hung',
          chunkSize: 1,
          window: 1,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(
          isA<SshWorkerTransportException>().having(
            (error) => error.code,
            'code',
            'transport_timeout',
          ),
        ),
      );

      expect(requests.map((request) => request.operation), [
        SshWorkerOperation.openSftpRead,
        SshWorkerOperation.cancelRequest,
      ]);
      expect(requests.first.args['timeoutMs'], 10);
    },
  );

  test('storage transfer parameters are validated in release-safe code', () {
    expect(
      () => SshWorkerStorageClient(_FakeStorageTransport(), chunkSize: 0),
      throwsArgumentError,
    );
    expect(
      () => SshWorkerStorageClient(
        _FakeStorageTransport(),
        chunkSize: sshWorkerMaxChunkSize + 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => SshWorkerStorageClient(_FakeStorageTransport(), writeChunkSize: 0),
      throwsArgumentError,
    );
    expect(
      () => SshWorkerStorageClient(
        _FakeStorageTransport(),
        writeChunkSize: sshWorkerMaxChunkSize + 1,
      ),
      throwsArgumentError,
    );
    expect(
      () =>
          SshWorkerStorageClient(_FakeStorageTransport(), maxInFlightChunks: 0),
      throwsArgumentError,
    );
    expect(
      () => SshWorkerStorageClient(
        _FakeStorageTransport(),
        maxInFlightChunks: sshWorkerMaxReadWindow + 1,
      ),
      throwsArgumentError,
    );
  });
}

final class _FakeStorageTransport implements SshWorkerStorageTransport {
  _FakeStorageTransport({
    this.failReadAtSequence,
    this.failWriteAtSequence,
    this.readChunkCount = 4,
    this.failCleanup = false,
    this.hangCleanup = false,
  });

  final int? failReadAtSequence;
  final int? failWriteAtSequence;
  final int readChunkCount;
  final bool failCleanup;
  final bool hangCleanup;
  final acknowledgedSequences = <int>[];
  final writtenChunkSizes = <int>[];
  final closedStreams = <String>[];
  final cancelledStreams = <String>[];
  var maxObservedUnacknowledgedChunks = 0;
  var maxConcurrentReads = 0;
  var activeReads = 0;
  var _readSequence = 0;
  var _writeSequence = 0;
  var _readOffset = 0;
  var _readChunkSize = 1;
  final unacknowledged = <int>{};
  var lastReadOffset = 0;

  @override
  Future<void> connect(
    SshProfile profile,
    SshWorkerDialTarget target, {
    Duration timeout = const Duration(seconds: 30),
  }) async {}

  @override
  Future<SshWorkerRunResult> run(
    String command, {
    bool stderr = true,
    Uint8List? stdin,
    Duration timeout = const Duration(seconds: 30),
  }) async => SshWorkerRunResult(
    stdout: Uint8List(0),
    stderr: Uint8List(0),
    exitCode: 0,
  );

  @override
  Future<SshWorkerFileStat> stat(String path, {Duration? timeout}) async =>
      const SshWorkerFileStat(kind: 'file');

  @override
  Future<List<SshWorkerDirectoryEntry>> listDirectory(
    String path, {
    Duration? timeout,
  }) async => const [];

  @override
  Future<void> mkdir(String path, {Duration? timeout}) async {}

  @override
  Future<String> readlink(String path, {Duration? timeout}) async => path;

  @override
  Future<String> realpath(String path, {Duration? timeout}) async => path;

  @override
  Future<void> remove(
    String path, {
    bool directory = false,
    Duration? timeout,
  }) async {}

  @override
  Future<String> openRead(
    String path, {
    required int chunkSize,
    required int window,
    int offset = 0,
    Duration? timeout,
  }) async {
    lastReadOffset = offset;
    _readOffset = offset;
    _readChunkSize = chunkSize;
    return 'read-${_readSequence++}';
  }

  @override
  Future<void> acknowledgeReadChunk(
    String streamId,
    int sequence, {
    Duration? timeout,
  }) async {
    unacknowledged.remove(sequence);
  }

  @override
  Future<SshWorkerFileChunk?> readChunk(
    String streamId, {
    required int sequence,
    int? ackSequence,
    Duration? timeout,
  }) async {
    if (ackSequence != null) unacknowledged.remove(ackSequence);
    activeReads++;
    if (activeReads > maxConcurrentReads) maxConcurrentReads = activeReads;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    activeReads--;
    if (sequence == failReadAtSequence) {
      throw const SshWorkerTransportException('read failed');
    }
    final offset = _readOffset + sequence * _readChunkSize;
    if (sequence >= readChunkCount) {
      return SshWorkerFileChunk(
        sequence: sequence,
        offset: offset,
        bytes: Uint8List(0),
        isFinal: true,
      );
    }
    unacknowledged.add(sequence);
    if (unacknowledged.length > maxObservedUnacknowledgedChunks) {
      maxObservedUnacknowledgedChunks = unacknowledged.length;
    }
    return SshWorkerFileChunk(
      sequence: sequence,
      offset: offset,
      bytes: Uint8List.fromList([offset]),
      isFinal: sequence == readChunkCount - 1,
    );
  }

  @override
  Future<String> openWrite(
    String path, {
    required int chunkSize,
    required bool append,
    Duration? timeout,
  }) async => 'write-${_writeSequence++}';

  @override
  Future<void> writeChunk(
    String streamId,
    SshWorkerFileChunk chunk, {
    Duration? timeout,
  }) async {
    if (chunk.sequence == failWriteAtSequence) {
      throw const SshWorkerTransportException('write failed');
    }
    acknowledgedSequences.add(chunk.sequence);
    writtenChunkSizes.add(chunk.bytes.length);
  }

  @override
  Future<void> closeStream(String streamId, {Duration? timeout}) async {
    if (hangCleanup) return Completer<void>().future;
    if (failCleanup) throw StateError('cleanup failed');
    closedStreams.add(streamId);
  }

  @override
  Future<void> cancelStream(String streamId, {Duration? timeout}) async {
    if (hangCleanup) return Completer<void>().future;
    if (failCleanup) throw StateError('cleanup failed');
    cancelledStreams.add(streamId);
  }
}
