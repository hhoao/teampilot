import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_auth_type.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_protocol.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_types.dart';

void main() {
  test('file chunks and run results keep binary payloads typed', () {
    final chunk = SshWorkerFileChunk(
      sequence: 0,
      offset: 0,
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    expect(chunk.toWire()['bytes'], isA<Uint8List>());

    final result = SshWorkerRunResult(
      stdout: Uint8List.fromList([1]),
      stderr: Uint8List.fromList([2]),
      exitCode: 0,
    );
    expect(result.toWire()['stdout'], isA<Uint8List>());
    expect(result.toWire()['stderr'], isA<Uint8List>());
  });

  test('request round-trips primitive fields and operation', () {
    const request = SshWorkerRequest(
      requestId: 'r1',
      operation: SshWorkerOperation.runStorage,
      args: {'command': 'printf ok', 'stderr': false},
    );

    final decoded = SshWorkerRequest.fromWire(request.toWire());

    expect(decoded.requestId, 'r1');
    expect(decoded.operation, SshWorkerOperation.runStorage);
    expect(decoded.args['command'], 'printf ok');
    expect(decoded.args['stderr'], false);
  });

  test('forwarding operations remain primitive worker requests', () {
    expect(
      SshWorkerOperation.values.map((operation) => operation.name),
      containsAll([
        'openForwardLocal',
        'openForwardRemote',
        'writeForwardChannel',
        'acknowledgeForwardOutput',
        'closeForwardChannel',
        'closeForward',
      ]),
    );
  });

  test('binary chunk carries stream sequencing and completion', () {
    final chunk = SshWorkerEvent.outputChunk(
      streamId: 'pty-1',
      sequence: 3,
      bytes: Uint8List.fromList([1, 2, 3]),
      isFinal: false,
    );

    final decoded = SshWorkerEvent.fromWire(chunk.toWire());

    expect(decoded.streamId, 'pty-1');
    expect(decoded.sequence, 3);
    expect(decoded.bytes, [1, 2, 3]);
    expect(decoded.isFinal, isFalse);
  });

  test('forward lifecycle events carry only primitive identities', () {
    final opened = SshWorkerEvent.forwardChannelOpened(
      forwardId: 'forward-1',
      channelId: 'forward-1/channel-0',
    );
    final closed = SshWorkerEvent.forwardClosed(
      forwardId: 'forward-1',
      errorCode: 'transport_error',
    );

    final decodedOpened = SshWorkerEvent.fromWire(opened.toWire());
    final decodedClosed = SshWorkerEvent.fromWire(closed.toWire());

    expect(decodedOpened.forwardId, 'forward-1');
    expect(decodedOpened.channelId, 'forward-1/channel-0');
    expect(decodedClosed.errorCode, 'transport_error');
  });

  test('exec output preserves stdout/stderr stream and final metadata', () {
    final output = SshWorkerEvent.execOutput(
      streamId: 'exec-1',
      sequence: 4,
      stream: SshWorkerExecStream.stderr,
      bytes: Uint8List.fromList([8, 9]),
    );
    final finalEvent = SshWorkerEvent.execOutput(
      streamId: 'exec-1',
      sequence: 5,
      bytes: Uint8List(0),
      isFinal: true,
      exitCode: 137,
    );

    final decoded = SshWorkerEvent.fromWire(output.toWire());
    final decodedFinal = SshWorkerEvent.fromWire(finalEvent.toWire());

    expect(decoded.stream, SshWorkerExecStream.stderr);
    expect(decoded.bytes, [8, 9]);
    expect(decodedFinal.isFinal, isTrue);
    expect(decodedFinal.exitCode, 137);
  });

  test('malformed operation and missing request id fail closed', () {
    expect(
      () => SshWorkerRequest.fromWire({'type': 'request', 'operation': 'bad'}),
      throwsFormatException,
    );
  });

  test('writeSftpChunk round-trips bounded binary request payload', () {
    final request = SshWorkerRequest(
      requestId: 'sftp-1',
      operation: SshWorkerOperation.writeSftpChunk,
      args: {'streamId': 'sftp-stream', 'sequence': 2},
      payload: Uint8List.fromList([4, 5, 6]),
    );

    final decoded = SshWorkerRequest.fromWire(request.toWire());

    expect(decoded.operation, SshWorkerOperation.writeSftpChunk);
    expect(decoded.payload, [4, 5, 6]);
  });

  test('writePty round-trips transferable binary request payload', () {
    final request = SshWorkerRequest(
      requestId: 'pty-1',
      operation: SshWorkerOperation.writePty,
      payload: Uint8List.fromList([7, 8, 9]),
    );
    final wire = request.toWire()
      ..['payload'] = TransferableTypedData.fromList([request.payload!]);

    final decoded = SshWorkerRequest.fromWire(wire);

    expect(decoded.operation, SshWorkerOperation.writePty);
    expect(decoded.payload, [7, 8, 9]);
  });

  test('reply round-trips success, failure, cancellation, and completion', () {
    final replies = [
      SshWorkerReply.success('r1', result: {'exitCode': 0}),
      SshWorkerReply.failure(
        'r2',
        const SshWorkerErrorRecord(code: 'auth_failed', message: 'denied'),
      ),
      SshWorkerReply.cancellation('r3'),
      SshWorkerReply.streamCompletion('r4'),
    ];

    expect(
      replies.map((reply) => SshWorkerReply.fromWire(reply.toWire()).kind),
      [
        SshWorkerReplyKind.success,
        SshWorkerReplyKind.failure,
        SshWorkerReplyKind.cancellation,
        SshWorkerReplyKind.streamCompletion,
      ],
    );
  });

  test('dial target serializes only primitives', () {
    const target = SshWorkerDialTarget(
      host: 'example.test',
      port: 2222,
      hostKeyFingerprints: ['SHA256:abc'],
    );
    final decodedTarget = SshWorkerDialTarget.fromWire(target.toWire());
    expect(decodedTarget.host, 'example.test');
    expect(decodedTarget.port, 2222);
    expect(decodedTarget.hostKeyFingerprints, ['SHA256:abc']);
  });

  test('auth challenge and reply preserve request correlation', () {
    final challenge = SshWorkerAuthChallenge.hostKey(
      requestId: 'auth-1',
      profileId: 'profile-1',
      keyType: 'ssh-ed25519',
      fingerprint: Uint8List.fromList([1, 2, 3]),
    );

    final decodedChallenge = SshWorkerAuthChallenge.fromWire(
      challenge.toWire(),
    );
    final decodedReply = SshWorkerAuthReply.fromWire(
      SshWorkerAuthReply.decision(
        requestId: decodedChallenge.requestId,
        value: true,
      ).toWire(),
    );

    expect(decodedChallenge.profileId, 'profile-1');
    expect(decodedChallenge.fingerprint, [1, 2, 3]);
    expect(decodedReply.requestId, 'auth-1');
    expect(decodedReply.accepted, isTrue);
  });

  test('negative sequence and oversized chunks fail closed', () {
    expect(
      () => SshWorkerEvent.fromWire({
        'version': sshWorkerProtocolVersion,
        'type': 'event',
        'kind': 'outputChunk',
        'streamId': 'pty-1',
        'sequence': -1,
        'bytes': Uint8List(1),
        'isFinal': false,
      }),
      throwsFormatException,
    );
    expect(
      () => SshWorkerEvent.fromWire({
        'version': sshWorkerProtocolVersion,
        'type': 'event',
        'kind': 'outputChunk',
        'streamId': 'pty-1',
        'sequence': 0,
        'bytes': Uint8List(sshWorkerMaxChunkSize + 1),
        'isFinal': false,
      }),
      throwsFormatException,
    );
  });

  test('storage DTO decoders reject malformed fields with FormatException', () {
    expect(
      () => SshWorkerRunResult.fromWire({
        'stdout': 1,
        'stderr': '',
        'exitCode': null,
        'signalName': null,
      }),
      throwsFormatException,
    );
    expect(
      () => SshWorkerFileChunk.fromWire({
        'sequence': '0',
        'offset': 0,
        'bytes': '',
        'eof': false,
      }),
      throwsFormatException,
    );
    expect(
      () => SshWorkerFileChunk.fromWire({
        'sequence': 0,
        'offset': 0,
        'bytes': '',
        'eof': null,
      }),
      throwsFormatException,
    );
    expect(
      () => SshWorkerFileStat.fromWire({
        'size': '1',
        'modifyTime': null,
        'kind': 'file',
      }),
      throwsFormatException,
    );
    expect(
      () => SshWorkerDirectoryEntry.fromWire({
        'name': 'file',
        'stat': 'not-a-map',
      }),
      throwsFormatException,
    );
  });

  test('storage DTOs preserve binary output and nullable process fields', () {
    final result = SshWorkerRunResult(
      stdout: Uint8List.fromList([0, 255, 1]),
      stderr: Uint8List.fromList([2, 0]),
    );
    final decodedResult = SshWorkerRunResult.fromWire(result.toWire());
    final chunk = SshWorkerFileChunk(
      sequence: 2,
      offset: 4,
      bytes: Uint8List.fromList([0, 255, 1]),
      isFinal: true,
    );
    final decodedChunk = SshWorkerFileChunk.fromWire(chunk.toWire());

    expect(decodedResult.stdout, [0, 255, 1]);
    expect(decodedResult.stderr, [2, 0]);
    expect(decodedResult.exitCode, isNull);
    expect(decodedChunk.bytes, [0, 255, 1]);
    expect(decodedChunk.isFinal, isTrue);
  });

  group('connection reference', () {
    const target = SshWorkerDialTarget(
      host: '10.0.0.5',
      port: 2222,
      hostKeyFingerprints: ['SHA256:abc'],
    );

    test('carries identity, not an address', () {
      const ref = SshWorkerConnectionRef(
        machineId: 'm1',
        generation: 7,
        username: 'alice',
        authType: SshAuthType.privateKey,
      );

      expect(ref.toArgs(), {
        'machineId': 'm1',
        'generation': 7,
        'username': 'alice',
        'authType': 'privateKey',
      });
      final decoded = SshWorkerConnectionRef.fromArgs(ref.toArgs());
      expect(decoded.machineId, 'm1');
      expect(decoded.generation, 7);
      expect(decoded.authType, SshAuthType.privateKey);
    });

    test('builds the dialer view from the endpoint attempt', () {
      const ref = SshWorkerConnectionRef(
        machineId: 'm1',
        generation: 1,
        username: 'alice',
        authType: SshAuthType.password,
      );

      final profile = ref.profileFor(target);

      expect(profile.id, 'm1');
      expect(profile.host, '10.0.0.5');
      expect(profile.port, 2222);
      expect(profile.username, 'alice');
      expect(profile.authType, SshAuthType.password);
      expect(profile.hostKeyFingerprints, ['SHA256:abc']);
    });

    test('rejects a missing or malformed identity', () {
      expect(
        () => SshWorkerConnectionRef.fromArgs({
          'username': 'alice',
          'authType': 'password',
        }),
        throwsFormatException,
      );
      expect(
        () => SshWorkerConnectionRef.fromArgs({
          'machineId': 'm1',
          'generation': 0,
          'username': 'alice',
          'authType': 'password',
        }),
        throwsFormatException,
      );
      expect(
        () => SshWorkerConnectionRef.fromArgs({
          'machineId': 'm1',
          'generation': 1,
          'username': 'alice',
          'authType': 'nope',
        }),
        throwsFormatException,
      );
    });

    test('a schema-1 request version is rejected', () {
      final wire = SshWorkerRequest(
        requestId: 'r1',
        operation: SshWorkerOperation.connectStorage,
        args: const {
          'machineId': 'm1',
          'generation': 1,
          'username': 'alice',
          'authType': 'password',
          'target': {'host': 'h', 'port': 22},
        },
      ).toWire();
      wire['version'] = 1;

      expect(
        () => SshWorkerRequest.fromWire(wire),
        throwsFormatException,
      );
    });
  });
}
