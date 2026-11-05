import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/ssh/ssh_transport_close.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_member_session.dart';
import 'package:teampilot/services/ssh/worker/ssh_profile_worker_manager.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_entry.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_protocol.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_types.dart';

void main() {
  test(
    'closing a member session closes its channel and releases its lease once',
    () async {
      final transport = _FakeMemberTransport();
      final session = await SshWorkerMemberSession.open(
        profile: _profile,
        transport: transport,
      );

      final channel = await session.openPty(columns: 80, rows: 24);
      transport.channel.emit(Uint8List.fromList([1, 2, 3]));
      transport.channel.finish(7);

      expect(await channel.output.single, [1, 2, 3]);
      expect(await channel.done, 7);

      await session.close();
      await session.close();

      expect(transport.closeCount, 1);
    },
  );

  test(
    'worker proxy acknowledges output and closes the member lease once',
    () async {
      final launcher = _MemberWorkerLauncher();
      final manager = SshProfileWorkerManager(launcher: launcher);
      final lease = await manager.acquire(_profile);
      final transport = SshWorkerLeaseMemberTransport(
        lease: lease,
        target: const SshWorkerDialTarget(host: '127.0.0.1', port: 22),
      );
      final session = await SshWorkerMemberSession.open(
        profile: _profile,
        transport: transport,
      );
      final channel = await session.openPty(columns: 80, rows: 24);
      final output = <Uint8List>[];
      final subscription = channel.output.listen(output.add);

      launcher.emitOutput(Uint8List.fromList([1, 2]), sequence: 0);
      await Future<void>.delayed(Duration.zero);
      launcher.emitOutput(
        Uint8List(0),
        sequence: 1,
        isFinal: true,
        exitCode: 7,
      );

      expect(await channel.done, 7);
      expect(output.single, [1, 2]);
      await Future<void>.delayed(Duration.zero);
      expect(
        launcher.operations,
        contains(SshWorkerOperation.acknowledgePtyOutput),
      );

      await session.close();
      await manager.flushIdleShutdowns();
      expect(launcher.closeChannelCount, 1);
      expect(launcher.shutdownCount, 1);
      await subscription.cancel();
    },
  );

  test('two leases on one worker use distinct member ids', () async {
    final launcher = _MemberWorkerLauncher();
    final manager = SshProfileWorkerManager(launcher: launcher);
    final leaseA = await manager.acquire(_profile);
    final leaseB = await manager.acquire(_profile);
    final transportA = SshWorkerLeaseMemberTransport(
      lease: leaseA,
      target: const SshWorkerDialTarget(host: '127.0.0.1', port: 22),
    );
    final transportB = SshWorkerLeaseMemberTransport(
      lease: leaseB,
      target: const SshWorkerDialTarget(host: '127.0.0.1', port: 22),
    );

    await SshWorkerMemberSession.open(profile: _profile, transport: transportA);
    await SshWorkerMemberSession.open(profile: _profile, transport: transportB);

    expect(launcher.memberIds, hasLength(2));
    expect(launcher.memberIds.toSet(), hasLength(2));

    await transportA.close();
    await transportB.close();
    await manager.flushIdleShutdowns();
  });

  test('a member transport close only tears down its own lease', () async {
    final launcher = _MemberWorkerLauncher();
    final manager = SshProfileWorkerManager(launcher: launcher);
    final leaseA = await manager.acquire(_profile);
    final leaseB = await manager.acquire(_profile);
    final transportA = SshWorkerLeaseMemberTransport(
      lease: leaseA,
      target: const SshWorkerDialTarget(host: '127.0.0.1', port: 22),
    );
    final transportB = SshWorkerLeaseMemberTransport(
      lease: leaseB,
      target: const SshWorkerDialTarget(host: '127.0.0.1', port: 22),
    );
    await SshWorkerMemberSession.open(profile: _profile, transport: transportA);
    await SshWorkerMemberSession.open(profile: _profile, transport: transportB);

    launcher.emitMemberClosed(launcher.memberIds.first);
    await Future<void>.delayed(Duration.zero);

    await expectLater(
      transportA.openPty(columns: 80, rows: 24),
      throwsStateError,
    );
    expect(await transportB.openPty(columns: 80, rows: 24), isNotNull);

    await transportA.close();
    await transportB.close();
    await manager.flushIdleShutdowns();
  });

  test('large PTY writes are split at the protocol chunk limit', () async {
    final launcher = _MemberWorkerLauncher();
    final manager = SshProfileWorkerManager(launcher: launcher);
    final lease = await manager.acquire(_profile);
    final transport = SshWorkerLeaseMemberTransport(
      lease: lease,
      target: const SshWorkerDialTarget(host: '127.0.0.1', port: 22),
    );
    final session = await SshWorkerMemberSession.open(
      profile: _profile,
      transport: transport,
    );
    final channel = await session.openPty(columns: 80, rows: 24);

    channel.write(Uint8List(sshWorkerMaxChunkSize + 1));
    await launcher.twoWrites.future.timeout(const Duration(seconds: 1));

    expect(launcher.writePayloadSizes, [sshWorkerMaxChunkSize, 1]);

    await session.close();
    await manager.flushIdleShutdowns();
  });

  test(
    'worker proxy buffers output and final sent before open reply',
    () async {
      final launcher = _MemberWorkerLauncher(outputBeforeOpenReply: true);
      final manager = SshProfileWorkerManager(launcher: launcher);
      final lease = await manager.acquire(_profile);
      final session = await SshWorkerMemberSession.open(
        profile: _profile,
        transport: SshWorkerLeaseMemberTransport(
          lease: lease,
          target: const SshWorkerDialTarget(host: '127.0.0.1', port: 22),
        ),
      );

      final channel = await session.openPty(columns: 80, rows: 24);

      expect(
        await channel.output.toList().timeout(
          const Duration(milliseconds: 100),
        ),
        [
          [4, 5, 6],
        ],
      );
      expect(await channel.done.timeout(const Duration(milliseconds: 100)), 7);
      await session.close();
      await manager.flushIdleShutdowns();
    },
  );

  test('closing while PTY open is pending rejects the late channel', () async {
    final openPtyReplyGate = Completer<void>();
    final launcher = _MemberWorkerLauncher(openPtyReplyGate: openPtyReplyGate);
    final manager = SshProfileWorkerManager(launcher: launcher);
    final lease = await manager.acquire(_profile);
    final transport = SshWorkerLeaseMemberTransport(
      lease: lease,
      target: const SshWorkerDialTarget(host: '127.0.0.1', port: 22),
    );
    await SshWorkerMemberSession.open(profile: _profile, transport: transport);

    final opening = transport.openPty(columns: 80, rows: 24);
    await launcher.openPtyRequested.future;
    final closing = transport.close();
    await Future<void>.delayed(Duration.zero);
    openPtyReplyGate.complete();

    await closing;
    await expectLater(opening, throwsA(isA<StateError>()));
    await manager.flushIdleShutdowns();
  });

  test(
    'out-of-order PTY output completes done with a protocol error',
    () async {
      final launcher = _MemberWorkerLauncher();
      final manager = SshProfileWorkerManager(launcher: launcher);
      final lease = await manager.acquire(_profile);
      final session = await SshWorkerMemberSession.open(
        profile: _profile,
        transport: SshWorkerLeaseMemberTransport(
          lease: lease,
          target: const SshWorkerDialTarget(host: '127.0.0.1', port: 22),
        ),
      );
      final channel = await session.openPty(columns: 80, rows: 24);

      launcher.emitOutput(
        Uint8List(0),
        sequence: 1,
        isFinal: true,
        exitCode: 9,
      );

      await expectLater(channel.done, throwsA(isA<SshWorkerMemberException>()));
      await session.close();
      await manager.flushIdleShutdowns();
    },
  );

  test('user PTY close preserves final output and normal done', () async {
    final launcher = _MemberWorkerLauncher(outputOnPtyClose: true);
    final manager = SshProfileWorkerManager(launcher: launcher);
    final lease = await manager.acquire(_profile);
    final session = await SshWorkerMemberSession.open(
      profile: _profile,
      transport: SshWorkerLeaseMemberTransport(
        lease: lease,
        target: const SshWorkerDialTarget(host: '127.0.0.1', port: 22),
      ),
    );
    final channel = await session.openPty(columns: 80, rows: 24);
    final output = channel.output.toList();

    channel.close();

    expect(await output.timeout(const Duration(milliseconds: 100)), [
      [8, 9],
    ]);
    expect(await channel.done.timeout(const Duration(milliseconds: 100)), 9);
    await session.close();
    await manager.flushIdleShutdowns();
  });

  test('member close does not turn its PTY final into an error', () async {
    final launcher = _MemberWorkerLauncher(outputOnMemberClose: true);
    final manager = SshProfileWorkerManager(launcher: launcher);
    final lease = await manager.acquire(_profile);
    final session = await SshWorkerMemberSession.open(
      profile: _profile,
      transport: SshWorkerLeaseMemberTransport(
        lease: lease,
        target: const SshWorkerDialTarget(host: '127.0.0.1', port: 22),
      ),
    );
    final channel = await session.openPty(columns: 80, rows: 24);
    final output = channel.output.toList();

    await session.close();

    expect(await output, [
      [10, 11],
    ]);
    expect(await channel.done, 11);
    await manager.flushIdleShutdowns();
  });

  test('late PTY ACK after final completion is harmless', () async {
    final acknowledgeGate = Completer<void>();
    final uncaughtErrors = <Object>[];
    await runZonedGuarded(
      () async {
        final launcher = _MemberWorkerLauncher(
          acknowledgeReplyGate: acknowledgeGate,
          failAcknowledgements: true,
        );
        final manager = SshProfileWorkerManager(launcher: launcher);
        final lease = await manager.acquire(_profile);
        final transport = SshWorkerLeaseMemberTransport(
          lease: lease,
          target: const SshWorkerDialTarget(host: '127.0.0.1', port: 22),
        );
        final session = await SshWorkerMemberSession.open(
          profile: _profile,
          transport: transport,
        );
        final channel = await session.openPty(columns: 80, rows: 24);

        launcher.emitOutput(Uint8List.fromList([1]), sequence: 0);
        launcher.emitOutput(
          Uint8List(0),
          sequence: 1,
          isFinal: true,
          exitCode: 7,
        );
        expect(await channel.done, 7);

        acknowledgeGate.complete();
        await Future<void>.delayed(Duration.zero);
        await session.close();
        await manager.flushIdleShutdowns();
      },
      (error, _) {
        uncaughtErrors.add(error);
      },
    );

    expect(uncaughtErrors, isEmpty);
  });

  test('worker message closure fails active PTY instead of hanging', () async {
    final launcher = _MemberWorkerLauncher();
    final manager = SshProfileWorkerManager(launcher: launcher);
    final lease = await manager.acquire(_profile);
    final session = await SshWorkerMemberSession.open(
      profile: _profile,
      transport: SshWorkerLeaseMemberTransport(
        lease: lease,
        target: const SshWorkerDialTarget(host: '127.0.0.1', port: 22),
      ),
    );
    final channel = await session.openPty(columns: 80, rows: 24);

    await launcher.crash();

    await expectLater(
      channel.done.timeout(const Duration(seconds: 1)),
      throwsA(isA<StateError>()),
    );
    await session.close().catchError((_) {});
    await manager.close();
  });

  test(
    'PTY write and resize failures complete the channel with error',
    () async {
      final launcher = _MemberWorkerLauncher(failPtyMutation: true);
      final manager = SshProfileWorkerManager(launcher: launcher);
      final lease = await manager.acquire(_profile);
      final session = await SshWorkerMemberSession.open(
        profile: _profile,
        transport: SshWorkerLeaseMemberTransport(
          lease: lease,
          target: const SshWorkerDialTarget(host: '127.0.0.1', port: 22),
        ),
      );
      final channel = await session.openPty(columns: 80, rows: 24);

      channel.write(Uint8List.fromList([1]));
      channel.resize(30, 100);

      await expectLater(
        channel.done.timeout(const Duration(seconds: 1)),
        throwsA(isA<SshWorkerMemberException>()),
      );
      await session.close().catchError((_) {});
      await manager.close();
    },
  );
}

const _profile = SshProfile(
  id: 'p1',
  name: 'Test',
  host: 'example.test',
  username: 'tester',
);

final class _FakeMemberTransport implements SshWorkerMemberTransport {
  final channel = _FakePtyChannel();
  var closeCount = 0;

  @override
  Future<void> open(
    SshProfile profile, {
    Duration timeout = Duration.zero,
  }) async {}

  @override
  Future<SshWorkerPtyChannel> openPty({
    String? command,
    required int columns,
    required int rows,
    Map<String, String>? environment,
  }) async => channel;

  @override
  Future<SshWorkerRunResult> run(String command, {bool stderr = true}) async =>
      SshWorkerRunResult(
        stdout: Uint8List(0),
        stderr: Uint8List(0),
        exitCode: 0,
        signalName: null,
      );

  @override
  Future<SshWorkerExecChannel> startProcess(String command) async =>
      throw UnsupportedError('not used by this test');

  @override
  Future<void> close() async {
    closeCount++;
  }
}

final class _FakePtyChannel implements SshWorkerPtyChannel {
  final _output = StreamController<Uint8List>();
  final _done = Completer<int>();

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get done => _done.future;

  @override
  void close() {
    if (!_done.isCompleted) finish(0);
  }

  void emit(Uint8List bytes) => _output.add(bytes);

  void finish(int exitCode) {
    if (!_done.isCompleted) _done.complete(exitCode);
    unawaited(_output.close());
  }

  @override
  void resize(int rows, int columns) {}

  @override
  void write(Uint8List data) {}
}

final class _MemberWorkerLauncher implements SshWorkerLauncher {
  _MemberWorkerLauncher({
    this.outputBeforeOpenReply = false,
    this.outputOnPtyClose = false,
    this.outputOnMemberClose = false,
    this.openPtyReplyGate,
    this.acknowledgeReplyGate,
    this.failAcknowledgements = false,
    this.failPtyMutation = false,
  });

  final bool outputBeforeOpenReply;
  final bool outputOnPtyClose;
  final bool outputOnMemberClose;
  final Completer<void>? openPtyReplyGate;
  final Completer<void>? acknowledgeReplyGate;
  final bool failAcknowledgements;
  final bool failPtyMutation;
  final operations = <SshWorkerOperation>[];
  final memberIds = <String>[];
  final _messages = StreamController<Object?>.broadcast();
  String? _ptyId;
  final openPtyRequested = Completer<void>();
  final writePayloadSizes = <int>[];
  final twoWrites = Completer<void>();
  var closeChannelCount = 0;
  var shutdownCount = 0;

  @override
  Future<SshWorkerLaunch> spawn({
    required SshProfile profile,
    required int generation,
    required String debugName,
  }) async {
    final commands = ReceivePort();
    commands.listen((wire) async {
      final request = SshWorkerRequest.fromWire(wire);
      operations.add(request.operation);
      switch (request.operation) {
        case SshWorkerOperation.openMember:
          memberIds.add(request.args['memberId']! as String);
          _success(request);
        case SshWorkerOperation.openPty:
          _ptyId = request.args['ptyId']! as String;
          if (!openPtyRequested.isCompleted) openPtyRequested.complete();
          if (outputBeforeOpenReply) {
            emitOutput(Uint8List.fromList([4, 5, 6]), sequence: 0);
            emitOutput(Uint8List(0), sequence: 1, isFinal: true, exitCode: 7);
          }
          await openPtyReplyGate?.future;
          _success(request);
        case SshWorkerOperation.closeChannel:
          closeChannelCount++;
          final channelId = request.args['channelId']! as String;
          if (channelId.contains('/') && outputOnPtyClose) {
            emitOutput(Uint8List.fromList([8, 9]), sequence: 0);
            emitOutput(Uint8List(0), sequence: 1, isFinal: true, exitCode: 9);
          } else if (!channelId.contains('/') && outputOnMemberClose) {
            _messages.add(
              SshWorkerEvent.transportClosed(
                plane: SshTransportPlane.member,
                reason: SshTransportCloseReason.memberSessionClosed,
              ).toWire(),
            );
            emitOutput(Uint8List.fromList([10, 11]), sequence: 0);
            emitOutput(Uint8List(0), sequence: 1, isFinal: true, exitCode: 11);
          }
          _success(request);
        case SshWorkerOperation.acknowledgePtyOutput:
          await acknowledgeReplyGate?.future;
          if (failAcknowledgements) {
            _messages.add(
              SshWorkerReply.failure(
                request.requestId,
                const SshWorkerErrorRecord(
                  code: 'channel_not_found',
                  message: 'PTY already completed',
                ),
              ).toWire(),
            );
          } else {
            _success(request);
          }
        case SshWorkerOperation.writePty:
          writePayloadSizes.add(request.payload?.length ?? 0);
          if (writePayloadSizes.length >= 2 && !twoWrites.isCompleted) {
            twoWrites.complete();
          }
          if (failPtyMutation) {
            _messages.add(
              SshWorkerReply.failure(
                request.requestId,
                const SshWorkerErrorRecord(
                  code: 'transport_error',
                  message: 'PTY mutation failed',
                ),
              ).toWire(),
            );
          } else {
            _success(request);
          }
        case SshWorkerOperation.resizePty:
          if (failPtyMutation) {
            _messages.add(
              SshWorkerReply.failure(
                request.requestId,
                const SshWorkerErrorRecord(
                  code: 'transport_error',
                  message: 'PTY mutation failed',
                ),
              ).toWire(),
            );
          } else {
            _success(request);
          }
        case SshWorkerOperation.shutdown:
          shutdownCount++;
          _success(request);
        default:
          _success(request);
      }
    });
    return SshWorkerLaunch(
      workerIdentity: Object(),
      commands: commands.sendPort,
      messages: _messages.stream,
      close: () async {
        commands.close();
        await _messages.close();
      },
    );
  }

  void emitOutput(
    Uint8List bytes, {
    required int sequence,
    bool isFinal = false,
    int? exitCode,
  }) {
    _messages.add(
      SshWorkerEvent.outputChunk(
        streamId: _ptyId!,
        sequence: sequence,
        bytes: bytes,
        isFinal: isFinal,
        exitCode: exitCode,
      ).toWire(),
    );
  }

  void emitMemberClosed(String memberId) {
    _messages.add(
      SshWorkerEvent.transportClosed(
        plane: SshTransportPlane.member,
        reason: SshTransportCloseReason.transportError,
        streamId: memberId,
      ).toWire(),
    );
  }

  void _success(SshWorkerRequest request) {
    _messages.add(SshWorkerReply.success(request.requestId).toWire());
  }

  Future<void> crash() => _messages.close();
}
