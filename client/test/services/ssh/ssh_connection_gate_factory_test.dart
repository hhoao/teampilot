import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_gate.dart';
import 'package:teampilot/services/ssh/worker/ssh_profile_worker_manager.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_entry.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_forward_proxy.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_protocol.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_types.dart';

const _profile = SshProfile(
  id: 'p1',
  name: 'test',
  host: 'example.test',
  username: 'tester',
);

void main() {
  test('concurrent cold-start storage opens share one dial', () async {
    final launcher = _ConnectLauncher();
    final gate = SshConnectionGate();
    final factory = _factory(launcher, gate);

    final clients = await Future.wait([
      for (var i = 0; i < 8; i++) factory.storageFor(_profile),
    ]);

    expect(clients.length, 8);
    expect(launcher.connectCount, 1);
    // Pure pool: a successful dial must not write dial state. The supervisor
    // owns the gate; the pool only reads its `beforeIo` guard.
    expect(gate.stateOf(_profile.id), SshConnectionGateState.idle);

    await factory.close();
    gate.dispose();
  });

  test(
    'a failed storage open leaves the gate to its owner',
    () async {
      final launcher = _ConnectLauncher(connectErrorCode: 'auth_aborted');
      final gate = SshConnectionGate();
      final factory = _factory(launcher, gate);

      await expectLater(
        factory.storageFor(_profile),
        throwsA(isA<SshWorkerTransportException>()),
      );
      expect(gate.stateOf(_profile.id), SshConnectionGateState.idle);
      expect(launcher.connectCount, 1);

      // Once the gate owner marks the profile down, the injected read-only
      // guard rejects I/O before any dial is attempted.
      gate.markDown(_profile.id);
      await expectLater(
        factory.storageFor(_profile),
        throwsA(isA<SshProfileDownException>()),
      );
      expect(launcher.connectCount, 1);

      await factory.close();
      gate.dispose();
    },
  );

  test('the pool cannot bypass a down gate on its own', () async {
    final launcher = _ConnectLauncher();
    final gate = SshConnectionGate();
    final factory = _factory(launcher, gate);

    gate.markDown(_profile.id);
    await expectLater(
      factory.ensureStorageConnected(_profile),
      throwsA(isA<SshProfileDownException>()),
    );
    expect(launcher.connectCount, 0);

    // Only the gate owner can re-arm it; then the pool dials as usual.
    gate.allowNextDial(_profile.id);
    await factory.ensureStorageConnected(_profile);
    expect(launcher.connectCount, 1);
    expect(gate.stateOf(_profile.id), SshConnectionGateState.connecting);

    await factory.close();
    gate.dispose();
  });

  test('a suspended gate rejects the reconnect driver', () async {
    final launcher = _ConnectLauncher();
    final gate = SshConnectionGate();
    final factory = _factory(launcher, gate);

    gate.suspend(_profile.id);
    await expectLater(
      factory.ensureStorageConnected(_profile),
      throwsA(isA<SshProfileDownException>()),
    );
    expect(launcher.connectCount, 0);

    await factory.close();
    gate.dispose();
  });

  test('a down gate rejects forward opens without sending a dial', () async {
    final launcher = _ConnectLauncher();
    final gate = SshConnectionGate();
    final factory = _factory(launcher, gate);

    gate.markDown(_profile.id);
    await expectLater(
      factory.openForwardChannel(_profile, '127.0.0.1', 8080),
      throwsA(isA<SshProfileDownException>()),
    );
    expect(
      launcher.operations,
      isNot(contains(SshWorkerOperation.openForwardLocal)),
    );

    await factory.close();
    gate.dispose();
  });

  test('a target-level forward failure does not touch the gate', () async {
    final launcher = _ConnectLauncher();
    final gate = SshConnectionGate();
    final factory = _factory(launcher, gate);

    await factory.storageFor(_profile);
    launcher.forwardErrorCode = 'open_failed';
    await expectLater(
      factory.openForwardChannel(_profile, '127.0.0.1', 8080),
      throwsA(isA<SshWorkerForwardException>()),
    );
    expect(gate.stateOf(_profile.id), SshConnectionGateState.idle);

    await factory.close();
    gate.dispose();
  });
}

SshClientFactory _factory(_ConnectLauncher launcher, SshConnectionGate gate) =>
    SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      workerManager: SshProfileWorkerManager(launcher: launcher),
      ioGuard: gate.beforeIo,
    );

final class _ConnectLauncher implements SshWorkerLauncher {
  _ConnectLauncher({this.connectErrorCode});

  String? connectErrorCode;
  String? forwardErrorCode;
  var connectCount = 0;
  final operations = <SshWorkerOperation>[];
  final Map<int, StreamController<Object?>> _messages = {};

  @override
  Future<SshWorkerLaunch> spawn({
    required SshProfile profile,
    required int generation,
    required String debugName,
  }) async {
    final messages = StreamController<Object?>.broadcast();
    _messages[generation] = messages;
    final commands = ReceivePort();
    commands.listen((wire) {
      final request = SshWorkerRequest.fromWire(wire);
      operations.add(request.operation);
      switch (request.operation) {
        case SshWorkerOperation.connectStorage:
          connectCount++;
          _reply(messages, request, connectErrorCode);
        case SshWorkerOperation.openForwardLocal:
          _reply(messages, request, forwardErrorCode);
        case SshWorkerOperation.disconnectStorage:
        case SshWorkerOperation.closeForward:
        case SshWorkerOperation.shutdown:
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

  void _reply(
    StreamController<Object?> messages,
    SshWorkerRequest request,
    String? errorCode,
  ) {
    if (errorCode != null) {
      messages.add(
        SshWorkerReply.failure(
          request.requestId,
          SshWorkerErrorRecord(code: errorCode, message: errorCode),
        ).toWire(),
      );
      return;
    }
    messages.add(SshWorkerReply.success(request.requestId).toWire());
  }
}
