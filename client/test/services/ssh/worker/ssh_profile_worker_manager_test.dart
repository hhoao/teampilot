import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/ssh/worker/ssh_profile_worker_client.dart';
import 'package:teampilot/services/ssh/worker/ssh_profile_worker_manager.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_metrics.dart';
import 'package:teampilot/services/ssh/worker/ssh_profile_worker.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_entry.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_protocol.dart';
import 'package:teampilot/services/ssh/ssh_transport_close.dart';

const testProfile = SshProfile(
  id: 'p1',
  name: 'Test profile',
  host: 'example.test',
  username: 'tester',
);

final staleReply = SshWorkerReply.success('stale-request');

void main() {
  test('same profile reuses one worker and reference counts leases', () async {
    final launcher = RecordingWorkerLauncher();
    final manager = SshProfileWorkerManager(launcher: launcher);

    final first = await manager.acquire(testProfile);
    final second = await manager.acquire(testProfile);

    expect(identical(first.workerIdentity, second.workerIdentity), isTrue);
    expect(launcher.spawnCount, 1);
    await first.release();
    expect(launcher.shutdownCount, 0);
    await second.release();
    await manager.flushIdleShutdowns();
    expect(launcher.shutdownCount, 1);

    await manager.close();
  });

  test(
    'enabled metrics observe the worker request and event lifecycle',
    () async {
      final launcher = RecordingWorkerLauncher();
      final metrics = SshWorkerMetrics(enabled: true, logDiagnostic: (_) {});
      final manager = SshProfileWorkerManager(
        launcher: launcher,
        metrics: metrics,
      );
      final lease = await manager.acquire(testProfile);

      await lease.send(
        const SshWorkerRequest(
          requestId: 'connect-1',
          operation: SshWorkerOperation.connectStorage,
        ),
      );
      await lease.send(
        SshWorkerRequest(
          requestId: 'write-1',
          operation: SshWorkerOperation.writeSftpChunk,
          payload: Uint8List.fromList([1, 2, 3]),
        ),
      );
      await lease.send(
        const SshWorkerRequest(
          requestId: 'forward-1',
          operation: SshWorkerOperation.openForwardLocal,
          args: {'forwardId': 'forward-1'},
        ),
      );
      launcher.emitEventFromGeneration(
        lease.generation,
        SshWorkerEvent.outputChunk(
          streamId: 'forward-1',
          sequence: 0,
          bytes: Uint8List.fromList([0]),
          isFinal: false,
        ),
      );
      launcher.emitEventFromGeneration(
        lease.generation,
        SshWorkerEvent.execOutput(
          streamId: 'exec-1',
          sequence: 0,
          stream: SshWorkerExecStream.stdout,
          bytes: Uint8List.fromList([4, 5]),
        ),
      );
      launcher.emitEventFromGeneration(
        lease.generation,
        SshWorkerEvent.forwardClosed(forwardId: 'forward-1'),
      );
      launcher.emitEventFromGeneration(
        lease.generation,
        SshWorkerEvent.outputChunk(
          streamId: 'forward-1',
          sequence: 1,
          bytes: Uint8List.fromList([6]),
          isFinal: false,
        ),
      );
      await lease.send(
        const SshWorkerRequest(
          requestId: 'forward-2',
          operation: SshWorkerOperation.openForwardLocal,
          args: {'forwardId': 'forward-1'},
        ),
      );
      launcher.emitEventFromGeneration(
        lease.generation,
        SshWorkerEvent.outputChunk(
          streamId: 'forward-1',
          sequence: 2,
          bytes: Uint8List.fromList([7]),
          isFinal: false,
        ),
      );
      await lease.send(
        const SshWorkerRequest(
          requestId: 'close-forward-1',
          operation: SshWorkerOperation.closeForward,
          args: {'forwardId': 'forward-1'},
        ),
      );
      launcher.emitEventFromGeneration(
        lease.generation,
        SshWorkerEvent.outputChunk(
          streamId: 'forward-1',
          sequence: 3,
          bytes: Uint8List.fromList([8]),
          isFinal: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(metrics.snapshot.activeWorkers, 1);
      expect(metrics.snapshot.completedRequestLatencies, hasLength(5));
      expect(metrics.snapshot.connectLatencies, hasLength(2));
      expect(metrics.snapshot.sftpBytesPerChunk, [3]);
      expect(metrics.snapshot.terminalBytesPerFrame, [2]);

      await lease.release();
      await manager.flushIdleShutdowns();
      expect(metrics.snapshot.activeWorkers, 0);
      expect(metrics.snapshot.workerShutdownDurations, hasLength(1));
      final reconnected = await manager.acquire(testProfile);
      await reconnected.send(
        const SshWorkerRequest(
          requestId: 'connect-2',
          operation: SshWorkerOperation.connectStorage,
        ),
      );
      expect(metrics.snapshot.reconnectLatencies, hasLength(2));
      await reconnected.release();
      await manager.flushIdleShutdowns();
      await manager.close();
    },
  );

  test(
    'queued forward output after forward close stays out of terminal metrics',
    () async {
      final launcher = RecordingWorkerLauncher();
      final metrics = SshWorkerMetrics(enabled: true, logDiagnostic: (_) {});
      final manager = SshProfileWorkerManager(
        launcher: launcher,
        metrics: metrics,
      );
      final lease = await manager.acquire(testProfile);

      await lease.send(
        const SshWorkerRequest(
          requestId: 'forward-open',
          operation: SshWorkerOperation.openForwardLocal,
          args: {'forwardId': 'forward-queued'},
        ),
      );
      launcher.emitEventFromGeneration(
        lease.generation,
        SshWorkerEvent.forwardClosed(forwardId: 'forward-queued'),
      );
      launcher.emitEventFromGeneration(
        lease.generation,
        SshWorkerEvent.outputChunk(
          streamId: 'forward-queued',
          sequence: 0,
          bytes: Uint8List.fromList([1, 2]),
          isFinal: false,
        ),
      );
      launcher.emitEventFromGeneration(
        lease.generation,
        SshWorkerEvent.outputChunk(
          streamId: 'forward-queued',
          sequence: 1,
          bytes: Uint8List(0),
          isFinal: true,
        ),
      );
      launcher.emitEventFromGeneration(
        lease.generation,
        SshWorkerEvent.outputChunk(
          streamId: 'forward-queued',
          sequence: 2,
          bytes: Uint8List.fromList([3]),
          isFinal: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(metrics.snapshot.terminalBytesPerFrame, [1]);

      await lease.release();
      await manager.flushIdleShutdowns();
      await manager.close();
    },
  );

  test(
    'transport close ends active connections in its plane for reconnect metrics',
    () async {
      final launcher = RecordingWorkerLauncher();
      final metrics = SshWorkerMetrics(enabled: true, logDiagnostic: (_) {});
      final manager = SshProfileWorkerManager(
        launcher: launcher,
        metrics: metrics,
      );
      final lease = await manager.acquire(testProfile);

      await lease.send(
        const SshWorkerRequest(
          requestId: 'storage-connect-1',
          operation: SshWorkerOperation.connectStorage,
        ),
      );
      await lease.send(
        const SshWorkerRequest(
          requestId: 'member-connect-1',
          operation: SshWorkerOperation.openMember,
          args: {'memberId': 'member-1'},
        ),
      );
      await lease.send(
        const SshWorkerRequest(
          requestId: 'member-connect-2',
          operation: SshWorkerOperation.openMember,
          args: {'memberId': 'member-2'},
        ),
      );

      launcher.emitEventFromGeneration(
        lease.generation,
        SshWorkerEvent.transportClosed(
          plane: SshTransportPlane.storage,
          reason: SshTransportCloseReason.transportError,
        ),
      );
      launcher.emitEventFromGeneration(
        lease.generation,
        SshWorkerEvent.transportClosed(
          plane: SshTransportPlane.member,
          reason: SshTransportCloseReason.remotePeerClosed,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      await lease.send(
        const SshWorkerRequest(
          requestId: 'storage-connect-2',
          operation: SshWorkerOperation.connectStorage,
        ),
      );
      await lease.send(
        const SshWorkerRequest(
          requestId: 'member-connect-3',
          operation: SshWorkerOperation.openMember,
          args: {'memberId': 'member-1'},
        ),
      );

      expect(metrics.snapshot.reconnectLatencies, hasLength(2));

      await lease.release();
      await manager.flushIdleShutdowns();
      await manager.close();
    },
  );

  test('lease rejects requests once shutdown begins', () async {
    final launcher = RecordingWorkerLauncher();
    final manager = SshProfileWorkerManager(launcher: launcher);
    final lease = await manager.acquire(testProfile);

    final disconnect = manager.disconnectProfile(testProfile.id);

    await expectLater(
      lease.send(
        const SshWorkerRequest(
          requestId: 'after-shutdown',
          operation: SshWorkerOperation.runStorage,
        ),
      ),
      throwsA(isA<StateError>()),
    );
    await disconnect;
    await lease.release();
    await manager.close();
  });

  test('failed SFTP writes do not count as transferred bytes', () async {
    final launcher = RecordingWorkerLauncher()
      ..failureRequestIds.add('failed-write');
    final metrics = SshWorkerMetrics(enabled: true, logDiagnostic: (_) {});
    final manager = SshProfileWorkerManager(
      launcher: launcher,
      metrics: metrics,
    );
    final lease = await manager.acquire(testProfile);

    final failed = await lease.send(
      SshWorkerRequest(
        requestId: 'failed-write',
        operation: SshWorkerOperation.writeSftpChunk,
        payload: Uint8List.fromList([1, 2, 3]),
      ),
    );
    expect(failed.kind, SshWorkerReplyKind.failure);
    expect(metrics.snapshot.sftpBytesTotal, 0);

    await lease.send(
      SshWorkerRequest(
        requestId: 'successful-write',
        operation: SshWorkerOperation.writeSftpChunk,
        payload: Uint8List.fromList([4, 5]),
      ),
    );
    expect(metrics.snapshot.sftpBytesPerChunk, [2]);

    await lease.release();
    await manager.flushIdleShutdowns();
    await manager.close();
  });

  test('failed forward opens release their tracked stream id', () async {
    final launcher = RecordingWorkerLauncher()
      ..failureRequestIds.add('failed-forward');
    final metrics = SshWorkerMetrics(enabled: true, logDiagnostic: (_) {});
    final manager = SshProfileWorkerManager(
      launcher: launcher,
      metrics: metrics,
    );
    final lease = await manager.acquire(testProfile);

    final failed = await lease.send(
      const SshWorkerRequest(
        requestId: 'failed-forward',
        operation: SshWorkerOperation.openForwardLocal,
        args: {'forwardId': 'forward-failed'},
      ),
    );
    expect(failed.kind, SshWorkerReplyKind.failure);
    launcher.emitEventFromGeneration(
      lease.generation,
      SshWorkerEvent.outputChunk(
        streamId: 'forward-failed',
        sequence: 0,
        bytes: Uint8List.fromList([1]),
        isFinal: false,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(metrics.snapshot.terminalBytesPerFrame, [1]);

    await lease.release();
    await manager.flushIdleShutdowns();
    await manager.close();
  });

  test('all active forward stream ids remain tracked until close', () async {
    final launcher = RecordingWorkerLauncher();
    final metrics = SshWorkerMetrics(enabled: true, logDiagnostic: (_) {});
    final manager = SshProfileWorkerManager(
      launcher: launcher,
      metrics: metrics,
    );
    final lease = await manager.acquire(testProfile);

    for (var index = 0; index < 257; index++) {
      await lease.send(
        SshWorkerRequest(
          requestId: 'open-forward-$index',
          operation: SshWorkerOperation.openForwardLocal,
          args: {'forwardId': 'forward-$index'},
        ),
      );
    }
    launcher.emitEventFromGeneration(
      lease.generation,
      SshWorkerEvent.outputChunk(
        streamId: 'forward-0',
        sequence: 0,
        bytes: Uint8List.fromList([1]),
        isFinal: false,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(metrics.snapshot.terminalBytesPerFrame, isEmpty);

    await lease.release();
    await manager.flushIdleShutdowns();
    await manager.close();
  });

  test('old worker events cannot complete a new generation', () async {
    final launcher = RecordingWorkerLauncher();
    final manager = SshProfileWorkerManager(launcher: launcher);
    final first = await manager.acquire(testProfile);
    await manager.disconnectProfile(testProfile.id);
    final second = await manager.acquire(testProfile);

    final pending = second.send(
      const SshWorkerRequest(
        requestId: 'stale-request',
        operation: SshWorkerOperation.runStorage,
      ),
    );
    launcher.emitFromGeneration(first.generation, staleReply);
    await Future<void>.delayed(Duration.zero);

    expect(second.pendingRequestIds, contains(staleReply.requestId));

    launcher.emitFromGeneration(second.generation, staleReply);
    expect((await pending).requestId, staleReply.requestId);

    await second.release();
    await manager.close();
  });

  test('forwards one close event from the active generation only', () async {
    final launcher = RecordingWorkerLauncher();
    final manager = SshProfileWorkerManager(launcher: launcher);
    final first = await manager.acquire(testProfile);
    await manager.disconnectProfile(testProfile.id);
    final second = await manager.acquire(testProfile);
    final received = <SshProfileWorkerManagerEvent>[];
    final subscription = manager.events.listen(received.add);

    launcher.emitEventFromGeneration(
      first.generation,
      SshWorkerEvent.transportClosed(
        plane: SshTransportPlane.storage,
        reason: SshTransportCloseReason.transportError,
      ),
    );
    launcher.emitEventFromGeneration(
      second.generation,
      SshWorkerEvent.transportClosed(
        plane: SshTransportPlane.member,
        reason: SshTransportCloseReason.remotePeerClosed,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.single.profileId, testProfile.id);
    expect(received.single.generation, second.generation);
    expect(received.single.event.plane, SshTransportPlane.member);

    await subscription.cancel();
    await second.release();
    await manager.close();
  });

  test(
    'drops an old event queued before disconnect once a new generation exists',
    () async {
      final launcher = RecordingWorkerLauncher();
      final manager = SshProfileWorkerManager(launcher: launcher);
      final first = await manager.acquire(testProfile);
      final received = <SshProfileWorkerManagerEvent>[];
      final subscription = manager.events.listen(received.add);
      subscription.pause();

      launcher.emitEventFromGeneration(
        first.generation,
        SshWorkerEvent.transportClosed(
          plane: SshTransportPlane.storage,
          reason: SshTransportCloseReason.transportError,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await manager.disconnectProfile(testProfile.id);
      final second = await manager.acquire(testProfile);

      subscription.resume();
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);

      await subscription.cancel();
      await second.release();
      await manager.close();
    },
  );

  test('worker entry is spawned with an explicit debug name', () async {
    final launcher = RecordingWorkerLauncher();
    final manager = SshProfileWorkerManager(launcher: launcher);
    await (await manager.acquire(testProfile)).release();

    expect(launcher.debugNames.single, 'ssh-profile-worker:p1');

    await manager.close();
  });

  test('isolate launcher closes messages when its isolate exits', () async {
    const launcher = IsolateSshWorkerLauncher(
      shutdownTimeout: Duration(milliseconds: 50),
    );
    final launch = await launcher.spawn(
      profile: testProfile,
      generation: 1,
      debugName: 'ssh-profile-worker:test-unexpected-exit',
    );
    final messagesDone = Completer<void>();
    final subscription = launch.messages.listen(
      (_) {},
      onDone: messagesDone.complete,
    );

    (launch.workerIdentity as Isolate).kill(priority: Isolate.immediate);

    await messagesDone.future.timeout(const Duration(seconds: 1));
    await subscription.cancel();
    await launch.close();
  });

  test(
    'message boundary closure fails pending requests and event stream',
    () async {
      final commands = ReceivePort();
      final messages = StreamController<Object?>.broadcast();
      final client = SshProfileWorkerClient(
        profileId: testProfile.id,
        generation: 1,
        launch: SshWorkerLaunch(
          workerIdentity: Object(),
          commands: commands.sendPort,
          messages: messages.stream,
          close: () async => commands.close(),
        ),
      );
      final eventsDone = Completer<void>();
      final eventsSeen = <SshWorkerEvent>[];
      final subscription = client.events.listen(
        eventsSeen.add,
        onDone: eventsDone.complete,
      );
      final connected = client.send(
        const SshWorkerRequest(
          requestId: 'connect-storage',
          operation: SshWorkerOperation.connectStorage,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      messages.add(SshWorkerReply.success('connect-storage').toWire());
      await connected;
      final pending = client.send(
        const SshWorkerRequest(
          requestId: 'pending-on-exit',
          operation: SshWorkerOperation.runStorage,
        ),
      );

      await messages.close();

      await expectLater(pending, throwsA(isA<StateError>()));
      await eventsDone.future.timeout(const Duration(seconds: 1));
      expect(eventsSeen, hasLength(1));
      expect(eventsSeen.single.plane, SshTransportPlane.storage);
      await expectLater(
        client.send(
          const SshWorkerRequest(
            requestId: 'after-exit',
            operation: SshWorkerOperation.runStorage,
          ),
        ),
        throwsA(isA<StateError>()),
      );
      await subscription.cancel();
      await client.close().catchError((_) {});
    },
  );

  test('manager replaces a generation whose message boundary closes', () async {
    final launcher = RecordingWorkerLauncher();
    final manager = SshProfileWorkerManager(launcher: launcher);
    final first = await manager.acquire(testProfile);

    await launcher.closeGeneration(first.generation);
    await Future<void>.delayed(Duration.zero);
    final second = await manager.acquire(testProfile);

    expect(second.generation, first.generation + 1);
    expect(launcher.spawnCount, 2);

    await first.release();
    await second.release();
    await manager.close();
  });

  test(
    'direct launcher invokes the worker actor in the current isolate',
    () async {
      final manager = SshProfileWorkerManager(
        launcher: DirectSshWorkerLauncher(),
      );
      final lease = await manager.acquire(testProfile);

      final reply = await lease.send(
        const SshWorkerRequest(
          requestId: 'unsupported',
          operation: SshWorkerOperation.runStorage,
        ),
      );

      expect(reply.kind, SshWorkerReplyKind.failure);
      expect(reply.error?.code, 'storage_not_connected');

      await lease.release();
      await manager.flushIdleShutdowns();
      await manager.close();
    },
  );

  test('client closes a silent worker after the shutdown timeout', () async {
    final commands = ReceivePort();
    final messages = StreamController<Object?>.broadcast();
    var closeCount = 0;
    final client = SshProfileWorkerClient(
      profileId: testProfile.id,
      generation: 1,
      shutdownTimeout: const Duration(milliseconds: 10),
      launch: SshWorkerLaunch(
        workerIdentity: Object(),
        commands: commands.sendPort,
        messages: messages.stream,
        close: () async {
          closeCount++;
          commands.close();
        },
      ),
    );

    try {
      final closed = await Future.any([
        client.close().then((_) => true, onError: (_, __) => true),
        Future<bool>.delayed(const Duration(seconds: 1), () => false),
      ]);

      expect(closed, isTrue);
      expect(closeCount, 1);
    } finally {
      commands.close();
      await messages.close();
    }
  });

  test('client routes correlated auth challenges back to the worker', () async {
    final commands = ReceivePort();
    final messages = StreamController<Object?>.broadcast();
    final reply = Completer<SshWorkerAuthReply>();
    commands.listen((wire) {
      if (wire is Map && wire['type'] == 'authReply') {
        reply.complete(SshWorkerAuthReply.fromWire(wire));
      } else if (wire is Map && wire['type'] == 'request') {
        final request = SshWorkerRequest.fromWire(wire);
        messages.add(SshWorkerReply.success(request.requestId).toWire());
      }
    });
    final client = SshProfileWorkerClient(
      profileId: testProfile.id,
      generation: 1,
      launch: SshWorkerLaunch(
        workerIdentity: Object(),
        commands: commands.sendPort,
        messages: messages.stream,
        close: () async => commands.close(),
      ),
      onAuthChallenge: (challenge) async {
        expect(challenge.profileId, testProfile.id);
        return SshWorkerAuthReply.secret(
          requestId: challenge.requestId,
          value: 'secret',
        );
      },
    );

    messages.add(
      SshWorkerAuthChallenge.password(
        requestId: 'auth-1',
        profileId: testProfile.id,
      ).toWire(),
    );

    final routed = await reply.future;
    expect(routed.requestId, 'auth-1');
    expect(routed.secretValue, 'secret');

    await client.close();
    await messages.close();
  });

  test('worker waits for a correlated auth reply', () async {
    final messages = StreamController<Object?>.broadcast();
    final unusedPort = ReceivePort();
    SendPort? commands;
    final subscription = messages.stream.listen((wire) {
      if (wire is! Map) return;
      if (wire['type'] == 'ready') {
        commands = wire['commandPort'] as SendPort;
      } else if (wire['type'] == 'authChallenge') {
        final challenge = SshWorkerAuthChallenge.fromWire(wire);
        commands!.send(
          SshWorkerAuthReply.decision(
            requestId: challenge.requestId,
            value: true,
          ).toWire(),
        );
      }
    });
    final worker = SshProfileWorker(
      bootstrap: SshWorkerBootstrap(
        profileId: testProfile.id,
        uiPort: unusedPort.sendPort,
      ),
      send: messages.add,
    );

    worker.start();
    await Future<void>.delayed(Duration.zero);
    final reply = await worker.requestAuth(
      SshWorkerAuthChallenge.dialTarget(
        requestId: 'unused',
        profileId: testProfile.id,
      ),
    );

    expect(reply.accepted, isTrue);
    await subscription.cancel();
    unusedPort.close();
    await messages.close();
  });
}

class RecordingWorkerLauncher implements SshWorkerLauncher {
  final List<String> debugNames = [];
  final Map<int, StreamController<Object?>> _events = {};
  final Set<String> failureRequestIds = {};

  var spawnCount = 0;
  var shutdownCount = 0;

  @override
  Future<SshWorkerLaunch> spawn({
    required SshProfile profile,
    required int generation,
    required String debugName,
  }) async {
    spawnCount++;
    debugNames.add(debugName);
    final events = StreamController<Object?>.broadcast();
    final commands = ReceivePort();
    _events[generation] = events;
    commands.listen((Object? wire) {
      final request = SshWorkerRequest.fromWire(wire);
      if (request.operation == SshWorkerOperation.shutdown) {
        shutdownCount++;
        events.add(SshWorkerReply.success(request.requestId).toWire());
        return;
      }
      if (failureRequestIds.contains(request.requestId)) {
        events.add(
          SshWorkerReply.failure(
            request.requestId,
            const SshWorkerErrorRecord(
              code: 'test_failure',
              message: 'test failure',
            ),
          ).toWire(),
        );
        return;
      }
      if (request.requestId != staleReply.requestId) {
        events.add(SshWorkerReply.success(request.requestId).toWire());
      }
    });
    return SshWorkerLaunch(
      workerIdentity: Object(),
      commands: commands.sendPort,
      messages: events.stream,
      close: () async {
        commands.close();
      },
    );
  }

  void emitFromGeneration(int generation, SshWorkerReply reply) {
    _events[generation]?.add(reply.toWire());
  }

  void emitEventFromGeneration(int generation, SshWorkerEvent event) {
    _events[generation]?.add(event.toWire());
  }

  Future<void> closeGeneration(int generation) async {
    await _events[generation]?.close();
  }
}
