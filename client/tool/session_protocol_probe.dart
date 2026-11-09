import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:teampilot/services/session_protocol/session_envelope.dart';
import 'package:teampilot/services/session_protocol/session_frame_codec.dart';
import 'package:teampilot/services/session_protocol/session_models.dart';

/// Loopback probe for the desktop session authority.
///
/// Run from `client/` while the desktop App is running the current build:
///
/// ```bash
/// dart run tool/session_protocol_probe.dart
/// dart run tool/session_protocol_probe.dart --watch 15
/// dart run tool/session_protocol_probe.dart --cancel <sessionId> --member <memberId>
/// ```
///
/// It reads `session-protocol.json`, connects to the loopback port, sends
/// `hello`, prints the snapshot/deltas, and optionally sends `turn.cancel`.
Future<void> main(List<String> args) async {
  final home = Platform.environment['HOME'] ?? '';
  final adPath =
      _option(args, '--ad') ??
      p.posix.join(
        home,
        '.local/share/com.hhoa.teampilot/session-protocol.json',
      );
  final watchSeconds = int.tryParse(_option(args, '--watch') ?? '') ?? 5;
  final cancelSession = _option(args, '--cancel');
  final cancelMember = _option(args, '--member') ?? '';

  final file = File(adPath);
  if (!file.existsSync()) {
    stderr.writeln('advertisement not found: $adPath');
    exitCode = 2;
    return;
  }
  final raw = jsonDecode(await file.readAsString());
  if (raw is! Map) {
    stderr.writeln('advertisement is not an object: $adPath');
    exitCode = 2;
    return;
  }
  final port = (raw['port'] as num?)?.toInt();
  if (port == null || port <= 0) {
    stderr.writeln('advertisement has no port: $adPath');
    exitCode = 2;
    return;
  }
  stdout.writeln(
    'connecting 127.0.0.1:$port (epoch=${raw['epoch']}, '
    'authority=${raw['authority']})',
  );

  final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
  final decoder = SessionFrameDecoder();
  final ready = Completer<int?>();
  final result = Completer<SessionIntentResult>();
  var intentId = 'probe-1';

  void send(
    String type, {
    SessionChannel channel = SessionChannel.control,
    Map<String, Object?> body = const {},
    String corr = '',
  }) {
    socket.add(
      encodeSessionFrame(
        SessionEnvelope(type: type, channel: channel, corr: corr, body: body),
      ),
    );
  }

  socket.listen(
    (data) {
      for (final envelope in decoder.add(data)) {
        switch (envelope.type) {
          case SessionMessageType.helloAck:
            final epoch = (envelope.body['epoch'] as num?)?.toInt();
            stdout.writeln('helloAck epoch=$epoch');
            if (!ready.isCompleted) ready.complete(epoch);
          case SessionMessageType.snapshot:
            final list = envelope.body['sessions'];
            final sessions = <SessionSnapshot>[];
            if (list is List) {
              for (final item in list) {
                final snapshot = SessionSnapshot.fromJson(item);
                if (snapshot != null) sessions.add(snapshot);
              }
            }
            stdout.writeln('snapshot sessions=${sessions.length}');
            for (final snapshot in sessions) {
              stdout.writeln(
                '  session=${snapshot.sessionId} '
                'workspace=${snapshot.workspaceId} rev=${snapshot.revision} '
                'epoch=${snapshot.epoch}',
              );
              for (final seat in snapshot.seats) {
                stdout.writeln(
                  '    seat=${seat.memberId} state=${seat.state} '
                  'busy=${seat.isBusy} ready=${seat.readyToChat} '
                  'disposition=${seat.disposition}',
                );
              }
            }
          case SessionMessageType.delta:
            final delta = SessionDelta.fromJson(envelope.body);
            if (delta != null) {
              stdout.writeln(
                'delta session=${delta.sessionId} '
                'rev=${delta.baseRevision}->${delta.revision} '
                'removed=${delta.removed} '
                'busy=${delta.seats.any((seat) => seat.isBusy)}',
              );
            }
          case SessionMessageType.content:
            final invalidation = SessionContentInvalidated.fromJson(
              envelope.body,
            );
            if (invalidation != null) {
              stdout.writeln(
                'content session=${invalidation.sessionId} '
                'seq=${invalidation.seq} kind=${invalidation.kind}',
              );
            }
          case SessionMessageType.contentDelta:
            final delta = SessionContentDelta.fromJson(envelope.body);
            if (delta != null) {
              stdout.writeln(
                'contentDelta session=${delta.sessionId} '
                'member=${delta.memberId} seq=${delta.seq} '
                'kind=${delta.kind} bytes=${delta.payload.length}',
              );
            }
          case SessionMessageType.attention:
            stdout.writeln('attention ${jsonEncode(envelope.body)}');
          case SessionMessageType.intentResult:
            final parsed = SessionIntentResult.fromJson(envelope.body);
            if (parsed != null) {
              stdout.writeln(
                'intentResult id=${parsed.id} status=${parsed.status.name} '
                'code=${parsed.code} revision=${parsed.revision}',
              );
              if (!result.isCompleted) result.complete(parsed);
            }
          case SessionMessageType.error:
            stdout.writeln('error ${jsonEncode(envelope.body)}');
          case SessionMessageType.ping:
            send(SessionMessageType.pong, corr: envelope.corr);
          default:
            stdout.writeln('${envelope.type} ${jsonEncode(envelope.body)}');
        }
      }
    },
    onDone: () {
      if (!ready.isCompleted) ready.complete(null);
      if (!result.isCompleted) {
        result.complete(
          const SessionIntentResult(
            id: '',
            status: SessionIntentStatus.rejected,
            code: 'closed',
          ),
        );
      }
    },
    onError: (Object error) {
      stderr.writeln('socket error: $error');
      if (!ready.isCompleted) ready.complete(null);
      if (!result.isCompleted) {
        result.complete(
          const SessionIntentResult(
            id: '',
            status: SessionIntentStatus.rejected,
            code: 'socket_error',
          ),
        );
      }
    },
  );

  send(
    SessionMessageType.hello,
    body: {
      'proto': sessionProtocolVersion,
      'device': 'session-protocol-probe',
      'caps': const [
        'state',
        'content.invalidated',
        'content.delta',
        'intent.turn.cancel',
      ],
    },
  );

  final epoch = await ready.future.timeout(
    const Duration(seconds: 5),
    onTimeout: () => null,
  );
  if (epoch == null) {
    stderr.writeln('no helloAck (is the desktop App on the current build?)');
    await socket.close();
    exitCode = 3;
    return;
  }

  if (cancelSession != null && cancelSession.trim().isNotEmpty) {
    intentId = 'probe-cancel-1';
    send(
      SessionMessageType.intent,
      corr: intentId,
      body: SessionIntent(
        id: intentId,
        op: 'turn.cancel',
        sessionId: cancelSession.trim(),
        memberId: cancelMember.trim(),
        expectedEpoch: epoch,
        deadline: DateTime.now().toUtc().add(const Duration(seconds: 5)),
      ).toJson(),
    );
    await result.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () => const SessionIntentResult(
        id: 'probe-cancel-1',
        status: SessionIntentStatus.expired,
        code: 'probe_timeout',
      ),
    );
  }

  stdout.writeln('watching ${watchSeconds}s ...');
  await Future<void>.delayed(Duration(seconds: watchSeconds));
  await socket.close();
}

String? _option(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    if (args[i] == name && i + 1 < args.length) return args[i + 1];
    if (args[i].startsWith('$name=')) {
      return args[i].substring(name.length + 1);
    }
  }
  return null;
}
