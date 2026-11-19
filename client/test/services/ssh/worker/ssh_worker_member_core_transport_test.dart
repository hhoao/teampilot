import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/ssh/ssh_transport_close.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_member_core.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_protocol.dart';

void main() {
  test('remote member close emits one member transport-close event', () async {
    final client = _DoneClient();
    final events = <SshWorkerEvent>[];
    final core = SshWorkerMemberCore(
      profileId: _profile.id,
      openClient:
          ({required profile, required target, required timeout}) async =>
              client,
      sendEvent: events.add,
    );

    final opened = await core.handle(
      SshWorkerRequest(
        requestId: 'open',
        operation: SshWorkerOperation.openMember,
        args: {
          'memberId': 'member-1',
          ..._connectionArgs(_profile),
          'target': const SshWorkerDialTarget(
            host: 'example.test',
            port: 22,
          ).toWire(),
          'timeoutMs': 1000,
        },
      ),
    );
    expect(opened.kind, SshWorkerReplyKind.success);

    client.finish();
    await Future<void>.delayed(Duration.zero);
    final closeEvents = events
        .where((event) => event.kind == SshWorkerEventKind.transportClose)
        .toList();
    expect(closeEvents, hasLength(1));
    expect(closeEvents.single.plane, SshTransportPlane.member);
    expect(closeEvents.single.reason, SshTransportCloseReason.transportError);

    final afterClose = await core.handle(
      const SshWorkerRequest(
        requestId: 'run-after-close',
        operation: SshWorkerOperation.runMember,
        args: {'memberId': 'member-1', 'command': 'true'},
      ),
    );
    expect(afterClose.error?.code, 'member_not_found');
  });
}

const _profile = SshProfile(
  id: 'p1',
  name: 'test',
  host: 'example.test',
  username: 'tester',
);

final class _DoneClient extends SSHClient {
  _DoneClient() : super(_FakeSocket(), username: 'tester');

  final _done = Completer<void>();

  @override
  Future<void> get authenticated => Future<void>.value();

  @override
  Future<void> get done => _done.future;

  @override
  bool get isClosed => _done.isCompleted;

  @override
  Future<void> disconnect() async => finish();

  void finish() {
    if (!_done.isCompleted) _done.complete();
  }
}

final class _FakeSocket implements SSHSocket {
  final _input = StreamController<Uint8List>();
  final _done = Completer<void>();

  @override
  Stream<Uint8List> get stream => _input.stream;

  @override
  StreamSink<List<int>> get sink => _NoopSink();

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
    await _input.close();
  }

  @override
  void destroy() {
    if (!_done.isCompleted) _done.complete();
    unawaited(_input.close());
  }
}

final class _NoopSink implements StreamSink<List<int>> {
  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.drain<void>();
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future<void>.value();
}

Map<String, Object?> _connectionArgs(SshProfile profile) => {
  'machineId': profile.id,
  'generation': 1,
  'username': profile.username,
  'authType': profile.authType.name,
};
