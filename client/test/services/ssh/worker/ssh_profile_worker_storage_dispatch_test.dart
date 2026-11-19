import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/ssh/worker/ssh_profile_worker.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_protocol.dart';

const _profile = SshProfile(
  id: 'p1',
  name: 'Test profile',
  host: 'example.test',
  username: 'tester',
);

void main() {
  test(
    'malformed forward request is dispatched to the forward boundary',
    () async {
      final replies = <SshWorkerReply>[];
      late SendPort commandPort;
      SshProfileWorker(
        bootstrap: SshWorkerBootstrap(
          profileId: _profile.id,
          uiPort: ReceivePort().sendPort,
        ),
        send: (message) {
          if (message is! Map) return;
          if (message['type'] == 'ready') {
            commandPort = message['commandPort'] as SendPort;
          } else if (message['type'] == 'reply') {
            replies.add(SshWorkerReply.fromWire(message));
          }
        },
      ).start();

      commandPort.send(
        const SshWorkerRequest(
          requestId: 'invalid-forward',
          operation: SshWorkerOperation.openForwardLocal,
          args: {'forwardId': 'forward-1'},
        ).toWire(),
      );
      await Future<void>.delayed(Duration.zero);

      expect(replies.single.error?.code, 'invalid_forward_request');
    },
  );

  test('malformed storage wire request replies using its request id', () async {
    final replies = <SshWorkerReply>[];
    final replyAvailable = <Completer<SshWorkerReply>>[];
    late SendPort commandPort;
    SshProfileWorker(
      bootstrap: SshWorkerBootstrap(
        profileId: _profile.id,
        uiPort: ReceivePort().sendPort,
      ),
      send: (message) {
        if (message is! Map) return;
        if (message['type'] == 'ready') {
          commandPort = message['commandPort'] as SendPort;
        } else if (message['type'] == 'reply') {
          final reply = SshWorkerReply.fromWire(message);
          if (replyAvailable.isNotEmpty) {
            replyAvailable.removeAt(0).complete(reply);
          } else {
            replies.add(reply);
          }
        }
      },
    ).start();

    Future<SshWorkerReply> nextReply() {
      if (replies.isNotEmpty) return Future.value(replies.removeAt(0));
      final completer = Completer<SshWorkerReply>();
      replyAvailable.add(completer);
      return completer.future;
    }

    commandPort.send({
      'version': 1,
      'type': 'request',
      'requestId': 'malformed-storage',
      'operation': SshWorkerOperation.runStorage.name,
      'args': 'not-a-map',
    });

    final reply = await nextReply();
    expect(reply.requestId, 'malformed-storage');
    expect(reply.error?.code, 'invalid_storage_request');
  });

  test(
    'invalid first storage connect replies and allows a later connect',
    () async {
      final replies = <SshWorkerReply>[];
      final replyAvailable = <Completer<SshWorkerReply>>[];
      late SendPort commandPort;
      SshProfileWorker(
        bootstrap: SshWorkerBootstrap(
          profileId: _profile.id,
          uiPort: ReceivePort().sendPort,
        ),
        send: (message) {
          if (message is! Map) return;
          if (message['type'] == 'ready') {
            commandPort = message['commandPort'] as SendPort;
            return;
          }
          if (message['type'] != 'reply') return;
          final reply = SshWorkerReply.fromWire(message);
          if (replyAvailable.isNotEmpty) {
            replyAvailable.removeAt(0).complete(reply);
          } else {
            replies.add(reply);
          }
        },
      ).start();

      Future<SshWorkerReply> nextReply() {
        if (replies.isNotEmpty) return Future.value(replies.removeAt(0));
        final completer = Completer<SshWorkerReply>();
        replyAvailable.add(completer);
        return completer.future;
      }

      commandPort.send(
        const SshWorkerRequest(
          requestId: 'invalid-first-connect',
          operation: SshWorkerOperation.connectStorage,
          args: {'machineId': 42, 'target': {}},
        ).toWire(),
      );
      final invalid = await nextReply();
      expect(invalid.error?.code, 'invalid_storage_request');

      commandPort.send(
        SshWorkerRequest(
          requestId: 'valid-connect',
          operation: SshWorkerOperation.connectStorage,
          args: {
            ..._connectionArgs(_profile),
            'target': const SshWorkerDialTarget(
              host: '127.0.0.1',
              port: 1,
            ).toWire(),
            'timeoutMs': 50,
          },
        ).toWire(),
      );
      final connect = await nextReply();
      expect(connect.error?.code, isNot('storage_not_connected'));
    },
  );

  test('connect rejects a profile belonging to another worker', () async {
    final replies = <Object?>[];
    late SendPort commandPort;
    SshProfileWorker(
      bootstrap: SshWorkerBootstrap(
        profileId: _profile.id,
        uiPort: ReceivePort().sendPort,
      ),
      send: (message) {
        if (message is Map && message['type'] == 'ready') {
          commandPort = message['commandPort'] as SendPort;
        } else if (message is Map && message['type'] == 'reply') {
          replies.add(message);
        }
      },
    ).start();

    commandPort.send(
      SshWorkerRequest(
        requestId: 'wrong-profile',
        operation: SshWorkerOperation.connectStorage,
        args: {
          ..._connectionArgs(_profile.copyWith(id: 'other')),
          'target': const SshWorkerDialTarget(
            host: '127.0.0.1',
            port: 1,
          ).toWire(),
        },
      ).toWire(),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      SshWorkerReply.fromWire(replies.single).error?.code,
      'invalid_storage_request',
    );
  });

  test('disconnectStorage succeeds without a connected storage core', () async {
    final replies = <SshWorkerReply>[];
    late SendPort commandPort;
    SshProfileWorker(
      bootstrap: SshWorkerBootstrap(
        profileId: _profile.id,
        uiPort: ReceivePort().sendPort,
      ),
      send: (message) {
        if (message is Map && message['type'] == 'ready') {
          commandPort = message['commandPort'] as SendPort;
        } else if (message is Map && message['type'] == 'reply') {
          replies.add(SshWorkerReply.fromWire(message));
        }
      },
    ).start();

    commandPort.send(
      const SshWorkerRequest(
        requestId: 'disconnect-storage',
        operation: SshWorkerOperation.disconnectStorage,
      ).toWire(),
    );
    await Future<void>.delayed(Duration.zero);

    expect(replies.single.kind, SshWorkerReplyKind.success);
  });
}

Map<String, Object?> _connectionArgs(SshProfile profile) => {
  'machineId': profile.id,
  'generation': 1,
  'username': profile.username,
  'authType': profile.authType.name,
};
