import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_protocol.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_backend.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_core.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_types.dart';

void main() {
  test(
    'worker stream requires an acknowledgement before releasing a read credit',
    () async {
      final backend = _FakeBackend()..readResult = Uint8List.fromList([1]);
      final core = SshWorkerStorageCore(backend: backend, sendEvent: (_) {});
      await core.handle(_request(SshWorkerOperation.connectStorage));
      await core.handle(
        _request(SshWorkerOperation.openSftpRead, {
          'streamId': 'r',
          'path': '/file',
          'chunkSize': 1,
          'window': 1,
        }),
      );

      final first = await core.handle(
        _request(SshWorkerOperation.readSftpChunk, {
          'streamId': 'r',
          'sequence': 0,
        }),
      );
      expect(first.kind, SshWorkerReplyKind.success);
      final blocked = await core.handle(
        _request(SshWorkerOperation.readSftpChunk, {
          'streamId': 'r',
          'sequence': 1,
        }),
      );
      expect(blocked.error?.code, 'read_window_full');
      expect(backend.readCalls, 1);
      await core.handle(
        _request(SshWorkerOperation.acknowledgeSftpChunk, {
          'streamId': 'r',
          'sequence': 0,
        }),
      );
      expect(
        (await core.handle(
          _request(SshWorkerOperation.closeSftpStream, {'streamId': 'r'}),
        )).kind,
        SshWorkerReplyKind.success,
      );
    },
  );

  test(
    'closing a stream cancels a pending worker read and closes its handle',
    () async {
      final backend = _FakeBackend()..pendingRead = Completer<Uint8List>();
      final core = SshWorkerStorageCore(backend: backend, sendEvent: (_) {});
      await core.handle(_request(SshWorkerOperation.connectStorage));
      await core.handle(
        _request(SshWorkerOperation.openSftpRead, {
          'streamId': 'r',
          'path': '/file',
          'chunkSize': 1,
        }),
      );
      final pending = core.handle(
        _request(SshWorkerOperation.readSftpChunk, {
          'streamId': 'r',
          'sequence': 0,
        }),
      );
      await Future<void>.delayed(Duration.zero);
      await core.handle(
        _request(SshWorkerOperation.cancelRequest, {'streamId': 'r'}),
      );
      expect((await pending).kind, SshWorkerReplyKind.cancellation);
      expect(backend.closeCalls, 1);
    },
  );

  test(
    'worker write advances only after backend persistence succeeds',
    () async {
      final backend = _FakeBackend()..failWrites = true;
      final core = SshWorkerStorageCore(backend: backend, sendEvent: (_) {});
      await core.handle(_request(SshWorkerOperation.connectStorage));
      await core.handle(
        _request(SshWorkerOperation.openSftpWrite, {
          'streamId': 'w',
          'path': '/file',
          'chunkSize': 1,
        }),
      );
      final reply = await core.handle(
        SshWorkerRequest(
          requestId: 'write',
          operation: SshWorkerOperation.writeSftpChunk,
          args: const {'streamId': 'w', 'sequence': 0, 'offset': 0},
          payload: Uint8List.fromList([7]),
        ),
      );
      expect(reply.kind, SshWorkerReplyKind.failure);
      expect(reply.error?.code, 'transport_error');
      expect(backend.writeCalls, 1);
    },
  );

  test(
    'worker rejects unsafe chunk and acknowledgement window sizes',
    () async {
      final backend = _FakeBackend();
      final core = SshWorkerStorageCore(backend: backend, sendEvent: (_) {});
      await core.handle(_request(SshWorkerOperation.connectStorage));

      for (final args in [
        {'streamId': 'zero-chunk', 'path': '/file', 'chunkSize': 0},
        {
          'streamId': 'zero-window',
          'path': '/file',
          'chunkSize': 1,
          'window': 0,
        },
        {
          'streamId': 'large-chunk',
          'path': '/file',
          'chunkSize': sshWorkerMaxChunkSize + 1,
        },
        {
          'streamId': 'large-window',
          'path': '/file',
          'chunkSize': 1,
          'window': sshWorkerMaxReadWindow + 1,
        },
      ]) {
        final reply = await core.handle(
          _request(SshWorkerOperation.openSftpRead, args),
        );
        expect(reply.kind, SshWorkerReplyKind.failure);
        expect(reply.error?.code, 'invalid_storage_request');
      }
    },
  );

  test('a read request can release its predecessor credit inline', () async {
    final backend = _FakeBackend()..readResult = Uint8List.fromList([1]);
    final core = SshWorkerStorageCore(backend: backend, sendEvent: (_) {});
    await core.handle(_request(SshWorkerOperation.connectStorage));
    await core.handle(
      _request(SshWorkerOperation.openSftpRead, {
        'streamId': 'r',
        'path': '/file',
        'chunkSize': 1,
        'window': 1,
      }),
    );

    expect(
      (await core.handle(
        _request(SshWorkerOperation.readSftpChunk, {
          'streamId': 'r',
          'sequence': 0,
        }),
      )).kind,
      SshWorkerReplyKind.success,
    );
    final next = await core.handle(
      _request(SshWorkerOperation.readSftpChunk, {
        'streamId': 'r',
        'sequence': 1,
        'ackSequence': 0,
      }),
    );
    expect(next.kind, SshWorkerReplyKind.success);
    expect(backend.readCalls, 2);
    await core.handle(
      _request(SshWorkerOperation.closeSftpStream, {'streamId': 'r'}),
    );
  });

  test('ranged reads compute chunk offsets from the requested start', () async {
    final backend = _FakeBackend()..readResult = Uint8List(2);
    final core = SshWorkerStorageCore(backend: backend, sendEvent: (_) {});
    await core.handle(_request(SshWorkerOperation.connectStorage));
    await core.handle(
      _request(SshWorkerOperation.openSftpRead, {
        'streamId': 'r',
        'path': '/file',
        'chunkSize': 2,
        'window': 2,
        'offset': 5,
      }),
    );

    final first = await core.handle(
      _request(SshWorkerOperation.readSftpChunk, {
        'streamId': 'r',
        'sequence': 0,
      }),
    );
    final second = await core.handle(
      _request(SshWorkerOperation.readSftpChunk, {
        'streamId': 'r',
        'sequence': 1,
      }),
    );

    expect(first.result['offset'], 5);
    expect(second.result['offset'], 7);
    expect(backend.readOffsets, [5, 7]);
    await core.handle(
      _request(SshWorkerOperation.closeSftpStream, {'streamId': 'r'}),
    );
  });

  test('worker strictly validates storage boolean arguments', () async {
    final backend = _FakeBackend();
    final core = SshWorkerStorageCore(backend: backend, sendEvent: (_) {});
    await core.handle(_request(SshWorkerOperation.connectStorage));

    for (final request in [
      _request(SshWorkerOperation.runStorage, {'command': 'true', 'stderr': 1}),
      _request(SshWorkerOperation.statSftp, {'path': '/file', 'directory': 1}),
      _request(SshWorkerOperation.openSftpWrite, {
        'streamId': 'w',
        'path': '/file',
        'append': 'yes',
      }),
    ]) {
      final reply = await core.handle(request);
      expect(reply.error?.code, 'invalid_storage_request');
    }
  });

  test(
    'invalid open arguments do not reserve a stream id or idle timer',
    () async {
      final backend = _FakeBackend();
      final core = SshWorkerStorageCore(backend: backend, sendEvent: (_) {});
      await core.handle(_request(SshWorkerOperation.connectStorage));

      final invalid = await core.handle(
        _request(SshWorkerOperation.openSftpWrite, {
          'streamId': 'w',
          'path': '/file',
          'append': 'yes',
        }),
      );
      expect(invalid.error?.code, 'invalid_storage_request');

      final valid = await core.handle(
        _request(SshWorkerOperation.openSftpWrite, {
          'streamId': 'w',
          'path': '/file',
        }),
      );
      expect(valid.kind, SshWorkerReplyKind.success);
      expect(backend.openCalls, 1);
      await core.handle(
        _request(SshWorkerOperation.closeSftpStream, {'streamId': 'w'}),
      );
    },
  );

  test('read cleanup cannot replace the original read failure', () async {
    final backend = _FakeBackend()
      ..failReads = true
      ..failCloses = true;
    final core = SshWorkerStorageCore(backend: backend, sendEvent: (_) {});
    await core.handle(_request(SshWorkerOperation.connectStorage));
    await core.handle(
      _request(SshWorkerOperation.openSftpRead, {
        'streamId': 'r',
        'path': '/file',
      }),
    );

    final reply = await core.handle(
      _request(SshWorkerOperation.readSftpChunk, {
        'streamId': 'r',
        'sequence': 0,
      }),
    );
    expect(reply.error?.code, 'transport_error');
  });

  test('a timed-out storage exec cancels only that command', () async {
    final events = <SshWorkerEvent>[];
    final backend = _FakeBackend()..hangRun = true;
    final core = SshWorkerStorageCore(backend: backend, sendEvent: events.add);
    await core.handle(_request(SshWorkerOperation.connectStorage));

    final reply = await core.handle(
      SshWorkerRequest(
        requestId: 'run-timeout',
        operation: SshWorkerOperation.runStorage,
        args: const {'command': 'sleep 600', 'stderr': true, 'timeoutMs': 10},
      ),
    );

    expect(reply.error?.code, 'command_timeout');
    expect(backend.cancelRunCalls, 1);
    expect(
      events.where((event) => event.kind == SshWorkerEventKind.transportClose),
      isEmpty,
    );

    backend.hangRun = false;
    final next = await core.handle(
      SshWorkerRequest(
        requestId: 'run-ok',
        operation: SshWorkerOperation.runStorage,
        args: const {'command': 'true', 'stderr': true},
      ),
    );
    expect(next.kind, SshWorkerReplyKind.success);
  });
}

SshWorkerRequest _request(
  SshWorkerOperation operation, [
  Map<String, Object?> args = const {},
]) => SshWorkerRequest(
  requestId: '${operation.name}-${args.hashCode}',
  operation: operation,
  args: args,
);

final class _FakeBackend implements SshWorkerStorageBackend {
  Uint8List readResult = Uint8List(0);
  Completer<Uint8List>? pendingRead;
  var readCalls = 0;
  final readOffsets = <int>[];
  var closeCalls = 0;
  var openCalls = 0;
  var writeCalls = 0;
  var failWrites = false;
  var failReads = false;
  var failCloses = false;
  var hangRun = false;
  var cancelRunCalls = 0;
  final _pendingRuns = <Completer<SshWorkerRunResult>>[];

  @override
  Future<void> connect(SshWorkerRequest request) async {}

  @override
  Future<SshWorkerRunResult> run(
    String command, {
    required bool stderr,
    Uint8List? stdin,
  }) {
    if (!hangRun) {
      return Future.value(
        SshWorkerRunResult(
          stdout: Uint8List(0),
          stderr: Uint8List(0),
          exitCode: 0,
        ),
      );
    }
    final pending = Completer<SshWorkerRunResult>();
    _pendingRuns.add(pending);
    return pending.future;
  }

  @override
  void cancelRun() {
    cancelRunCalls++;
    for (final pending in _pendingRuns) {
      if (!pending.isCompleted) {
        pending.completeError(
          const SshWorkerTransportException('cancelled', code: 'cancelled'),
        );
      }
    }
    _pendingRuns.clear();
  }

  @override
  Future<Map<String, Object?>> metadata(
    SshWorkerOperation operation,
    String path, {
    bool directory = false,
  }) => throw UnimplementedError();

  @override
  Future<SshWorkerStorageFile> open(
    String path, {
    required bool write,
    required bool append,
  }) async {
    openCalls++;
    return _FakeFile(this, write);
  }

  @override
  void close() {}
}

final class _FakeFile implements SshWorkerStorageFile {
  _FakeFile(this.owner, this.writeMode);
  final _FakeBackend owner;
  final bool writeMode;

  @override
  Future<Uint8List> read(int offset, int length) {
    owner.readCalls++;
    owner.readOffsets.add(offset);
    if (owner.failReads)
      return Future.error(const SshWorkerTransportException('read failed'));
    final pending = owner.pendingRead;
    return pending == null ? Future.value(owner.readResult) : pending.future;
  }

  @override
  Future<void> write(Uint8List bytes, int offset) {
    owner.writeCalls++;
    if (owner.failWrites)
      return Future.error(const SshWorkerTransportException('write failed'));
    return Future.value();
  }

  @override
  Future<void> close() async {
    owner.closeCalls++;
    if (owner.failCloses) throw StateError('close failed');
  }
}
