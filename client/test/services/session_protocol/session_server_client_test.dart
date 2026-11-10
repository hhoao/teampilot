import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session_protocol/session_authority.dart';
import 'package:teampilot/services/session_protocol/session_channel.dart';
import 'package:teampilot/services/session_protocol/session_client.dart';
import 'package:teampilot/services/session_protocol/session_control_port.dart';
import 'package:teampilot/services/session_protocol/session_models.dart';
import 'package:teampilot/services/session_protocol/session_server.dart';

final class _Control implements SessionControlPort {
  int cancels = 0;
  final List<String> refreshes = [];
  final List<Map<String, Object?>> adopted = [];

  @override
  Future<void> cancelTurn({
    required String sessionId,
    required String memberId,
  }) async {
    cancels++;
  }

  @override
  Future<void> refreshWorkspaceSessions(String workspaceId) async {
    refreshes.add(workspaceId);
  }

  @override
  Future<void> adoptSession({
    required String workspaceId,
    required Map<String, Object?> entry,
  }) async {
    adopted.add(entry);
  }
}

final class _Pipe {
  _Pipe() {
    server = _Channel(this, isServer: true);
    client = _Channel(this, isServer: false);
  }

  late final _Channel server;
  late final _Channel client;

  void forward(_Channel from, List<int> data) {
    final target = identical(from, server) ? client : server;
    target.push(data);
  }
}

final class _Channel implements SessionByteChannel {
  _Channel(this._pipe, {required this.isServer});

  final _Pipe _pipe;
  final bool isServer;
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  bool closed = false;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  void add(List<int> data) => _pipe.forward(this, data);

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await _incoming.close();
  }

  void push(List<int> data) {
    if (!_incoming.isClosed) _incoming.add(data);
  }
}

Future<void> _waitFor(bool Function() ok, {Duration? timeout}) async {
  final end = DateTime.now().add(timeout ?? const Duration(seconds: 2));
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

SessionSeatActivity _seat(String state) => SessionSeatActivity(
  sessionId: 's1',
  memberId: 'dev',
  state: state,
  readyToChat: state == SessionSeatActivity.stateIdle,
);

void main() {
  test(
    'server and client exchange snapshot, delta, intent and attention',
    () async {
      final pipe = _Pipe();
      final control = _Control();
      final authority = SessionAuthority(
        authorityId: 'desk',
        controlPort: control,
        epoch: 7,
      );
      final server = SessionServer(
        channel: pipe.server,
        authority: authority,
        deviceId: 'desk',
      );
      var snapshots = 0;
      final deltas = <SessionDelta>[];
      final contents = <SessionContentInvalidated>[];
      final contentDeltas = <SessionContentDelta>[];
      final sessionLists = <SessionListDelta>[];
      final attentions = <SessionAttention>[];
      final client = SessionClient(
        channel: pipe.client,
        deviceId: 'phone',
        callbacks: SessionClientCallbacks(
          onSnapshot: (value) => snapshots++,
          onDelta: deltas.add,
          onContent: contents.add,
          onContentDelta: contentDeltas.add,
          onSessionList: sessionLists.add,
          onAttention: attentions.add,
        ),
      );

      await server.start();
      await client.start();
      await _waitFor(() => client.isReady && snapshots > 0);

      authority.updateSeats('s1', [
        _seat(SessionSeatActivity.stateWorking),
      ], workspaceId: 'ws1');
      await _waitFor(() => deltas.isNotEmpty);
      expect(deltas.last.seats.single.state, 'working');
      expect(deltas.last.workspaceId, 'ws1');

      final result = await client.cancelTurn(sessionId: 's1', memberId: 'dev');
      expect(result.status, SessionIntentStatus.applied);
      expect(control.cancels, 1);

      final refresh = await client.refreshSessions(workspaceId: 'ws1');
      expect(refresh.status, SessionIntentStatus.applied);
      expect(control.refreshes, ['ws1']);

      const entry = <String, Object?>{
        'sessionId': 's-new',
        'display': 'From mobile',
        'createdAt': 10,
      };
      final created = await client.createSession(
        workspaceId: 'ws1',
        sessionId: 's-new',
        entry: entry,
      );
      expect(created.status, SessionIntentStatus.applied);
      expect(control.adopted, [entry]);
      await _waitFor(() => sessionLists.isNotEmpty);
      expect(sessionLists.single.workspaceId, 'ws1');
      expect(sessionLists.single.upserted, [entry]);

      authority.publishContentInvalidated(sessionId: 's1');
      await _waitFor(() => contents.isNotEmpty);
      expect(contents.single.sessionId, 's1');

      authority.publishContentDelta(
        sessionId: 's1',
        memberId: 'dev',
        kind: 'acp.messages',
        payload: '{"v":2,"type":"reset"}\n',
      );
      await _waitFor(() => contentDeltas.isNotEmpty);
      expect(contentDeltas.single.kind, 'acp.messages');
      expect(contentDeltas.single.seq, 1);
      expect(contentDeltas.single.payload, '{"v":2,"type":"reset"}\n');

      authority.publishContentDelta(
        sessionId: 's1',
        memberId: 'dev',
        kind: 'acp.messages',
        payload: '{"v":2,"type":"part"}\n',
      );
      await _waitFor(() => contentDeltas.length == 2);
      expect(contentDeltas.last.seq, 2);
      expect(contentDeltas.last.baseSeq, 1);

      authority.publishAttention(sessionId: 's1', kind: 'idle', id: 'a1');
      await _waitFor(() => attentions.isNotEmpty);
      expect(attentions.single.kind, 'idle');

      await client.close();
      await server.stop();
      await authority.dispose();
    },
  );

  test('client cancel is a noop when the turn already ended', () async {
    final pipe = _Pipe();
    final control = _Control();
    final authority = SessionAuthority(
      authorityId: 'desk',
      controlPort: control,
      epoch: 7,
    );
    final server = SessionServer(
      channel: pipe.server,
      authority: authority,
      deviceId: 'desk',
    );
    final client = SessionClient(channel: pipe.client, deviceId: 'phone');

    await server.start();
    await client.start();
    await _waitFor(() => client.isReady);

    authority.updateSeats('s1', [_seat(SessionSeatActivity.stateIdle)]);
    final result = await client.cancelTurn(sessionId: 's1', memberId: 'dev');

    expect(result.status, SessionIntentStatus.noop);
    expect(control.cancels, 0);

    await client.close();
    await server.stop();
    await authority.dispose();
  });
}
