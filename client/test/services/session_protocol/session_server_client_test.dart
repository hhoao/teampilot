import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/attention/attention_batch.dart';
import 'package:teampilot/services/attention/attention_cursor.dart';
import 'package:teampilot/services/attention/attention_event.dart';
import 'package:teampilot/services/attention/attention_log.dart';
import 'package:teampilot/services/session_protocol/session_authority.dart';
import 'package:teampilot/services/session_protocol/session_channel.dart';
import 'package:teampilot/services/session_protocol/session_client.dart';
import 'package:teampilot/services/session_protocol/session_control_port.dart';
import 'package:teampilot/services/session_protocol/session_envelope.dart';
import 'package:teampilot/services/session_protocol/session_frame_codec.dart';
import 'package:teampilot/services/session_protocol/session_models.dart';
import 'package:teampilot/services/session_protocol/session_server.dart';

final class _Control implements SessionControlPort {
  int cancels = 0;
  final List<String> refreshes = [];
  final List<Map<String, Object?>> adopted = [];
  final List<String> removed = [];
  final List<(String, String, String)> edits = [];
  final List<String> editCancels = [];

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

  @override
  Future<void> removeSession({
    required String workspaceId,
    required String sessionId,
  }) async {
    removed.add(sessionId);
  }

  @override
  Future<void> editTurn({
    required String sessionId,
    required String memberId,
    required String operationId,
    required String userMessageId,
    required String text,
  }) async {
    edits.add((operationId, userMessageId, text));
  }

  @override
  Future<void> cancelEdit({
    required String sessionId,
    required String memberId,
    required String operationId,
  }) async {
    editCancels.add(operationId);
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
    'server and client exchange snapshot, delta, intent and attention events',
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
      final batches = <AttentionBatch>[];
      final errors = <String>[];
      final client = SessionClient(
        channel: pipe.client,
        deviceId: 'phone',
        callbacks: SessionClientCallbacks(
          onSnapshot: (value) => snapshots++,
          onDelta: deltas.add,
          onContent: contents.add,
          onContentDelta: contentDeltas.add,
          onSessionList: sessionLists.add,
          onAttentionBatch: batches.add,
          onError: (code, message) => errors.add(code),
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

      final removed = await client.removeSession(
        workspaceId: 'ws1',
        sessionId: 's-new',
      );
      expect(removed.status, SessionIntentStatus.applied);
      expect(control.removed, ['s-new']);
      await _waitFor(() => sessionLists.length == 2);
      expect(sessionLists.last.workspaceId, 'ws1');
      expect(sessionLists.last.removed, ['s-new']);

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

      await authority.publishAttention(
        sessionId: 's1',
        kind: AttentionKind.idle,
        memberId: 'dev',
      );
      await _waitFor(() => batches.isNotEmpty);
      expect(batches.single.events.single.kind, AttentionKind.idle);
      expect(batches.single.events.single.seq, 1);

      client.sendAttentionAck(
        authorityId: 'desk',
        epoch: 7,
        seq: batches.single.toSeq,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(errors, isEmpty);

      await client.close();
      await server.stop();
      await authority.dispose();
    },
  );

  test('reconnect replays events after the client cursor', () async {
    final control = _Control();
    final authority = SessionAuthority(
      authorityId: 'desk',
      controlPort: control,
      epoch: 7,
    );

    final firstPipe = _Pipe();
    final firstBatches = <AttentionBatch>[];
    final firstServer = SessionServer(
      channel: firstPipe.server,
      authority: authority,
      deviceId: 'desk',
    );
    final firstClient = SessionClient(
      channel: firstPipe.client,
      deviceId: 'phone',
      callbacks: SessionClientCallbacks(onAttentionBatch: firstBatches.add),
    );
    await firstServer.start();
    await firstClient.start();
    await _waitFor(() => firstClient.isReady);

    await authority.publishAttention(sessionId: 's1', kind: AttentionKind.idle);
    await _waitFor(() => firstBatches.isNotEmpty);
    final cursor = AttentionCursor(
      authorityId: 'desk',
      epoch: 7,
      seq: firstBatches.single.toSeq,
    );

    await firstClient.close();
    await firstServer.stop();

    await authority.publishAttention(sessionId: 's2', kind: AttentionKind.idle);

    final secondPipe = _Pipe();
    final secondBatches = <AttentionBatch>[];
    final secondServer = SessionServer(
      channel: secondPipe.server,
      authority: authority,
      deviceId: 'desk',
    );
    final secondClient = SessionClient(
      channel: secondPipe.client,
      deviceId: 'phone',
      attentionCursors: () => {'desk': cursor},
      callbacks: SessionClientCallbacks(onAttentionBatch: secondBatches.add),
    );
    await secondServer.start();
    await secondClient.start();
    await _waitFor(() => secondBatches.isNotEmpty);

    expect(secondBatches.single.events.single.sessionId, 's2');
    expect(secondBatches.single.events.single.seq, 2);

    await secondClient.close();
    await secondServer.stop();
    await authority.dispose();
  });

  test(
    'an epoch mismatch starts from live instead of replaying old events',
    () async {
      final authority = SessionAuthority(
        authorityId: 'desk',
        controlPort: _Control(),
        epoch: 7,
      );
      await authority.publishAttention(
        sessionId: 'old',
        kind: AttentionKind.idle,
      );

      final pipe = _Pipe();
      final batches = <AttentionBatch>[];
      final server = SessionServer(
        channel: pipe.server,
        authority: authority,
        deviceId: 'desk',
      );
      final client = SessionClient(
        channel: pipe.client,
        deviceId: 'phone',
        attentionCursors: () => const {
          'desk': AttentionCursor(authorityId: 'desk', epoch: 6, seq: 1),
        },
        callbacks: SessionClientCallbacks(onAttentionBatch: batches.add),
      );
      await server.start();
      await client.start();
      await _waitFor(() => client.isReady);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(batches, isEmpty);

      await authority.publishAttention(
        sessionId: 'new',
        kind: AttentionKind.idle,
      );
      await _waitFor(() => batches.isNotEmpty);
      expect(batches.single.events.single.sessionId, 'new');

      await client.close();
      await server.stop();
      await authority.dispose();
    },
  );

  test('a cursor older than the retained window reports a gap', () async {
    final log = AttentionLog(authorityId: 'desk', epoch: 7, maxEvents: 2);
    final authority = SessionAuthority(
      authorityId: 'desk',
      controlPort: _Control(),
      epoch: 7,
      attentionLog: log,
    );
    for (var i = 0; i < 3; i++) {
      await authority.publishAttention(
        sessionId: 's$i',
        kind: AttentionKind.idle,
      );
    }

    final pipe = _Pipe();
    final batches = <AttentionBatch>[];
    final server = SessionServer(
      channel: pipe.server,
      authority: authority,
      deviceId: 'desk',
    );
    final client = SessionClient(
      channel: pipe.client,
      deviceId: 'phone',
      attentionCursors: () => const {
        'desk': AttentionCursor(authorityId: 'desk', epoch: 7, seq: 0),
      },
      callbacks: SessionClientCallbacks(onAttentionBatch: batches.add),
    );
    await server.start();
    await client.start();
    await _waitFor(() => batches.isNotEmpty);

    expect(batches.any((batch) => batch.gap), isTrue);
    expect(batches.expand((batch) => batch.events).map((event) => event.seq), [
      2,
      3,
    ]);

    await client.close();
    await server.stop();
    await authority.dispose();
  });

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

  test(
    'large backlogs are split below the frame limit and all events arrive once',
    () async {
      final log = AttentionLog(authorityId: 'desk', epoch: 7);
      final authority = SessionAuthority(
        authorityId: 'desk',
        controlPort: _Control(),
        epoch: 7,
        attentionLog: log,
      );
      final payload = 'x' * 8192;
      for (var i = 0; i < 180; i++) {
        await authority.publishAttention(
          sessionId: 's$i',
          kind: AttentionKind.idle,
          memberId: 'dev',
          title: payload,
          message: payload,
        );
      }

      final pipe = _Pipe();
      final batches = <AttentionBatch>[];
      final server = SessionServer(
        channel: pipe.server,
        authority: authority,
        deviceId: 'desk',
      );
      final client = SessionClient(
        channel: pipe.client,
        deviceId: 'phone',
        attentionCursors: () => const {
          'desk': AttentionCursor(authorityId: 'desk', epoch: 7, seq: 0),
        },
        callbacks: SessionClientCallbacks(onAttentionBatch: batches.add),
      );
      await server.start();
      await client.start();
      await _waitFor(
        () => batches.expand((b) => b.events).length == 180,
        timeout: const Duration(seconds: 10),
      );

      final seqs = batches.expand((b) => b.events).map((e) => e.seq).toList();
      expect(seqs, List<int>.generate(180, (i) => i + 1));
      expect(batches.length, greaterThan(1));
      for (final batch in batches) {
        final size = encodeSessionFrame(
          SessionEnvelope(
            type: SessionMessageType.events,
            channel: SessionChannel.events,
            seq: 1,
            body: batch.toJson(),
          ),
        ).length;
        expect(size, lessThanOrEqualTo(sessionMaxFrameBytes));
      }

      await client.close();
      await server.stop();
      await authority.dispose();
    },
  );
}
