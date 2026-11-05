import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_member_session.dart';
import 'package:teampilot/services/ssh/ssh_transport_close.dart';
import 'package:teampilot/services/chat/team_bus/remote/reverse_tunnel.dart';
import 'package:teampilot/services/ssh/worker/ssh_profile_worker_manager.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_entry.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_protocol.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_types.dart';

void main() {
  test('storage connections are owned by one profile worker', () async {
    final launcher = _StorageWorkerLauncher();
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      workerManager: SshProfileWorkerManager(launcher: launcher),
    );
    const profile = SshProfile(
      id: 'p1',
      name: 'test',
      host: 'example.test',
      username: 'tester',
    );

    final first = await factory.storageFor(
      profile,
      timeout: const Duration(milliseconds: 37),
    );
    final second = await factory.storageFor(profile);
    final result = await factory.runOnStorage(profile, 'printf ok');

    expect(identical(first, second), isTrue);
    expect(launcher.spawnCount, 1);
    expect(launcher.connectTimeouts, [37]);
    expect(result.stdout, [111, 107]);
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(factory.hasLiveStorageClient(profile.id), isTrue);

    factory.disconnectProfile(profile.id);
    await Future<void>.delayed(Duration.zero);
    expect(factory.hasLiveStorageClient(profile.id), isFalse);
  });

  test('a storage timeout does not stop the profile worker', () async {
    final runGate = Completer<void>();
    final launcher = _StorageWorkerLauncher(runGate: runGate);
    final manager = SshProfileWorkerManager(launcher: launcher);
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      workerManager: manager,
    );
    const profile = SshProfile(
      id: 'p1',
      name: 'test',
      host: 'example.test',
      username: 'tester',
    );

    await factory.storageFor(profile);
    await expectLater(
      factory.runOnStorage(
        profile,
        'slow',
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await Future<void>.delayed(Duration.zero);

    expect(launcher.operations, contains(SshWorkerOperation.disconnectStorage));
    expect(launcher.shutdownCount, 0);
    runGate.complete();
    await factory.close();
  });

  test(
    'runOnStorage keeps captures and defines output as stdout then stderr',
    () async {
      final launcher = _StorageWorkerLauncher(
        runResult: SshWorkerRunResult(
          stdout: Uint8List.fromList([1]),
          stderr: Uint8List.fromList([2, 3]),
          exitCode: null,
          signalName: 'TERM',
        ),
      );
      final factory = SshClientFactory(
        credentialStore: InMemorySshCredentialStore(),
        knownHostRepository: InMemorySshKnownHostRepository(),
        workerManager: SshProfileWorkerManager(launcher: launcher),
      );
      const profile = SshProfile(
        id: 'p1',
        name: 'test',
        host: 'example.test',
        username: 'tester',
      );

      final result = await factory.runOnStorage(profile, 'signal');

      expect(result.output, [1, 2, 3]);
      expect(result.stdout, [1]);
      expect(result.stderr, [2, 3]);
      expect(result.exitCode, isNull);
      expect(result.exitSignal?.signalName, 'TERM');
    },
  );

  test(
    'worker transport close clears the storage pool and emits a change',
    () async {
      final launcher = _StorageWorkerLauncher();
      final events = SshConnectionEvents();
      final closes = <SshTransportClosed>[];
      events.onTransportClosed = (_, error, _) {
        if (error is SshTransportClosed) closes.add(error);
      };
      final factory = SshClientFactory(
        credentialStore: InMemorySshCredentialStore(),
        knownHostRepository: InMemorySshKnownHostRepository(),
        events: events,
        workerManager: SshProfileWorkerManager(launcher: launcher),
      );
      const profile = SshProfile(
        id: 'p1',
        name: 'test',
        host: 'example.test',
        username: 'tester',
      );
      final changes = <String>[];
      final subscription = factory.storagePoolChanges.listen(changes.add);

      await factory.storageFor(profile);
      launcher.emitTransportClosed(1);
      await Future<void>.delayed(Duration.zero);

      expect(factory.hasLiveStorageClient(profile.id), isFalse);
      expect(changes, [profile.id, profile.id]);
      expect(closes, hasLength(1));
      expect(closes.single.plane, SshTransportPlane.storage);
      expect(closes.single.reason, SshTransportCloseReason.transportError);
      await subscription.cancel();
    },
  );

  test(
    'disconnectProfile drains a tracked worker operation before shutdown',
    () async {
      final runGate = Completer<void>();
      final launcher = _StorageWorkerLauncher(runGate: runGate);
      final factory = SshClientFactory(
        credentialStore: InMemorySshCredentialStore(),
        knownHostRepository: InMemorySshKnownHostRepository(),
        workerManager: SshProfileWorkerManager(launcher: launcher),
        drainGracePeriod: const Duration(seconds: 1),
      );
      const profile = SshProfile(
        id: 'p1',
        name: 'test',
        host: 'example.test',
        username: 'tester',
      );

      final operation = factory.runOnStorage(profile, 'long-running');
      await launcher.runRequested.future;

      factory.disconnectProfile(profile.id);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(factory.hasLiveStorageClient(profile.id), isFalse);
      expect(launcher.shutdownCount, 0);

      runGate.complete();
      final result = await operation;
      expect(result.stdout, [111, 107]);

      await launcher.shutdownRequested.future;
      expect(launcher.shutdownCount, 1);
    },
  );

  test('raw storage clients require the injected direct test seam', () async {
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      workerManager: SshProfileWorkerManager(
        launcher: _StorageWorkerLauncher(),
      ),
    );
    const profile = SshProfile(
      id: 'p1',
      name: 'test',
      host: 'example.test',
      username: 'tester',
    );

    await expectLater(factory.clientForStorage(profile), throwsStateError);
    await expectLater(factory.sftpFor(profile), throwsStateError);
    await expectLater(factory.createEphemeralClient(profile), throwsStateError);
    await expectLater(factory.createMemberClient(profile), throwsStateError);
    await expectLater(factory.createClient(profile), throwsStateError);
  });

  test('testConnection uses a detached profile worker', () async {
    final launcher = _StorageWorkerLauncher();
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      workerManager: SshProfileWorkerManager(launcher: launcher),
    );

    await factory.testConnection(_profile, password: 'form-password');

    expect(launcher.spawnCount, 1);
    expect(launcher.connectTimeouts, [10000]);
    await launcher.shutdownRequested.future;
    expect(launcher.shutdownCount, 1);
    expect(factory.hasLiveStorageClient(_profile.id), isFalse);
    await factory.close();
  });

  test(
    'worker exec timeout preserves TimeoutException and evicts storage',
    () async {
      final factory = SshClientFactory(
        credentialStore: InMemorySshCredentialStore(),
        knownHostRepository: InMemorySshKnownHostRepository(),
        workerManager: SshProfileWorkerManager(
          launcher: _StorageWorkerLauncher(runErrorCode: 'transport_timeout'),
        ),
      );
      const profile = SshProfile(
        id: 'p1',
        name: 'test',
        host: 'example.test',
        username: 'tester',
      );

      await expectLater(
        factory.runOnStorage(profile, 'slow'),
        throwsA(isA<TimeoutException>()),
      );
      expect(factory.hasLiveStorageClient(profile.id), isFalse);
    },
  );

  test('startProcess exposes output before the worker command exits', () async {
    final runGate = Completer<void>();
    final launcher = _MemberWorkerLauncher(streamExec: true, runGate: runGate);
    final manager = SshProfileWorkerManager(launcher: launcher);
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      workerManager: manager,
    );

    final handle = await factory.startProcess(_profile, 'printf worker');
    final firstOutput = await handle.stdout.first.timeout(
      const Duration(milliseconds: 100),
    );

    expect(firstOutput, [1, 2]);
    expect(runGate.isCompleted, isFalse);
    runGate.complete();
    expect(await handle.stderr.first, [3]);
    expect(await handle.exitCode, 17);
    expect(launcher.operations, [
      SshWorkerOperation.openMember,
      SshWorkerOperation.startMemberExec,
      SshWorkerOperation.acknowledgeExecOutput,
      SshWorkerOperation.acknowledgeExecOutput,
      SshWorkerOperation.closeChannel,
    ]);
    await manager.flushIdleShutdowns();
  });

  test('startProcess kill sends KILL to the worker exec session', () async {
    final runGate = Completer<void>();
    final launcher = _MemberWorkerLauncher(streamExec: true, runGate: runGate);
    final manager = SshProfileWorkerManager(launcher: launcher);
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      workerManager: manager,
    );

    final handle = await factory.startProcess(_profile, 'sleep 60');
    handle.kill();

    expect(
      await launcher.killRequested.future.timeout(
        const Duration(milliseconds: 100),
      ),
      SshWorkerOperation.killMemberExec,
    );
    expect(await handle.exitCode, 137);
    runGate.complete();
    await manager.flushIdleShutdowns();
  });

  test('worker member exposes an injected narrow reverse tunnel', () async {
    final launcher = _MemberWorkerLauncher();
    final manager = SshProfileWorkerManager(launcher: launcher);
    final tunnel = _FakeReverseTunnel();
    String? requestedBindHost;
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      workerManager: manager,
      memberReverseTunnelFactory: (profile, {required bindHost}) {
        expect(profile, _profile);
        requestedBindHost = bindHost;
        return tunnel;
      },
    );
    final session = await SshMemberSession.open(factory, _profile);

    final created = session.newReverseTunnel(bindHost: '0.0.0.0');

    expect(created, same(tunnel));
    expect(requestedBindHost, '0.0.0.0');
    await session.close();
    await manager.flushIdleShutdowns();
  });
}

const _profile = SshProfile(
  id: 'p1',
  name: 'test',
  host: 'example.test',
  username: 'tester',
);

final class _StorageWorkerLauncher implements SshWorkerLauncher {
  _StorageWorkerLauncher({this.runGate, this.runErrorCode, this.runResult});

  final Completer<void>? runGate;
  final String? runErrorCode;
  final SshWorkerRunResult? runResult;
  var spawnCount = 0;
  var shutdownCount = 0;
  final operations = <SshWorkerOperation>[];
  final runRequested = Completer<void>();
  final shutdownRequested = Completer<void>();
  final connectTimeouts = <int>[];
  final Map<int, StreamController<Object?>> _messages = {};

  @override
  Future<SshWorkerLaunch> spawn({
    required SshProfile profile,
    required int generation,
    required String debugName,
  }) async {
    spawnCount++;
    final messages = StreamController<Object?>.broadcast();
    _messages[generation] = messages;
    final commands = ReceivePort();
    commands.listen((wire) async {
      final request = SshWorkerRequest.fromWire(wire);
      operations.add(request.operation);
      switch (request.operation) {
        case SshWorkerOperation.connectStorage:
          connectTimeouts.add(request.args['timeoutMs']! as int);
          messages.add(SshWorkerReply.success(request.requestId).toWire());
        case SshWorkerOperation.runStorage:
          if (!runRequested.isCompleted) runRequested.complete();
          await runGate?.future;
          final errorCode = runErrorCode;
          if (errorCode != null) {
            messages.add(
              SshWorkerReply.failure(
                request.requestId,
                SshWorkerErrorRecord(code: errorCode, message: errorCode),
              ).toWire(),
            );
            return;
          }
          messages.add(
            SshWorkerReply.success(
              request.requestId,
              result:
                  (runResult ??
                          SshWorkerRunResult(
                            stdout: Uint8List.fromList([111, 107]),
                            stderr: Uint8List(0),
                            exitCode: 0,
                            signalName: null,
                          ))
                      .toWire(),
            ).toWire(),
          );
        case SshWorkerOperation.shutdown:
          shutdownCount++;
          if (!shutdownRequested.isCompleted) shutdownRequested.complete();
          messages.add(SshWorkerReply.success(request.requestId).toWire());
        default:
          messages.add(
            SshWorkerReply.failure(
              request.requestId,
              const SshWorkerErrorRecord(
                code: 'unsupported_operation',
                message: 'unsupported',
              ),
            ).toWire(),
          );
      }
    });
    return SshWorkerLaunch(
      workerIdentity: Object(),
      commands: commands.sendPort,
      messages: messages.stream,
      close: () async {
        commands.close();
        await messages.close();
      },
    );
  }

  void emitTransportClosed(int generation) {
    _messages[generation]!.add(
      SshWorkerEvent.transportClosed(
        plane: SshTransportPlane.storage,
        reason: SshTransportCloseReason.transportError,
      ).toWire(),
    );
  }
}

final class _MemberWorkerLauncher implements SshWorkerLauncher {
  _MemberWorkerLauncher({this.streamExec = false, this.runGate});

  final bool streamExec;
  final Completer<void>? runGate;
  final operations = <SshWorkerOperation>[];
  final killRequested = Completer<SshWorkerOperation>();

  @override
  Future<SshWorkerLaunch> spawn({
    required SshProfile profile,
    required int generation,
    required String debugName,
  }) async {
    final messages = StreamController<Object?>.broadcast();
    final commands = ReceivePort();
    commands.listen((wire) async {
      final request = SshWorkerRequest.fromWire(wire);
      if (request.operation == SshWorkerOperation.shutdown) {
        messages.add(SshWorkerReply.success(request.requestId).toWire());
        return;
      }
      operations.add(request.operation);
      if (request.operation == SshWorkerOperation.startMemberExec) {
        final execId = request.args['execId']! as String;
        messages.add(
          SshWorkerReply.success(
            request.requestId,
            result: {'execId': execId},
          ).toWire(),
        );
        if (streamExec) {
          messages.add(
            SshWorkerEvent.execOutput(
              streamId: execId,
              sequence: 0,
              stream: SshWorkerExecStream.stdout,
              bytes: Uint8List.fromList([1, 2]),
            ).toWire(),
          );
          await runGate?.future;
        }
        messages.add(
          SshWorkerEvent.execOutput(
            streamId: execId,
            sequence: 1,
            stream: SshWorkerExecStream.stderr,
            bytes: Uint8List.fromList([3]),
          ).toWire(),
        );
        messages.add(
          SshWorkerEvent.execOutput(
            streamId: execId,
            sequence: 2,
            bytes: Uint8List(0),
            isFinal: true,
            exitCode: 17,
          ).toWire(),
        );
        return;
      }
      if (request.operation == SshWorkerOperation.killMemberExec) {
        if (!killRequested.isCompleted) {
          killRequested.complete(request.operation);
        }
        final execId = request.args['execId']! as String;
        messages.add(SshWorkerReply.success(request.requestId).toWire());
        messages.add(
          SshWorkerEvent.execOutput(
            streamId: execId,
            sequence: 1,
            bytes: Uint8List(0),
            isFinal: true,
            exitCode: 137,
          ).toWire(),
        );
        return;
      }
      final result = switch (request.operation) {
        SshWorkerOperation.runMember => SshWorkerRunResult(
          stdout: Uint8List.fromList([1, 2]),
          stderr: Uint8List.fromList([3]),
          exitCode: 17,
          signalName: null,
        ).toWire(),
        _ => const <String, Object?>{},
      };
      messages.add(
        SshWorkerReply.success(request.requestId, result: result).toWire(),
      );
    });
    return SshWorkerLaunch(
      workerIdentity: Object(),
      commands: commands.sendPort,
      messages: messages.stream,
      close: () async {
        commands.close();
        await messages.close();
      },
    );
  }
}

final class _FakeReverseTunnel implements ReverseTunnel {
  @override
  Stream<TunnelChannel> get channels => const Stream.empty();

  @override
  Future<void> close() async {}

  @override
  Future<int> open() async => 49152;
}
