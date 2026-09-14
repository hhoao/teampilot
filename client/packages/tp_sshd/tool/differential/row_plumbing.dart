/// Shared plumbing for the tp_sshd differential audit rows.
///
/// The probe scaffolding (row construction, the both-server run + crash
/// isolation loop, observation rendering, the sshd-log cross-check, the
/// session-channel open/exec scaffolding) was written per-area while Areas A
/// and B were produced, so it exists duplicated in `area_a_malformed.dart`
/// and `area_b_rekey.dart`. Those completed files keep their local copies
/// untouched (audit-history rule: a filled-in area's runner does not churn);
/// from Area C on, every area uses this file instead.
///
/// VM-only tool code: `dart:io` sockets and processes.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' show SSHClient, SSHKeyPair, SSHSocket;
import 'package:dartssh2/protocol.dart';

import 'area_a_malformed.dart' show AuditRow;
import 'audit_harness.dart';
import 'raw_driver.dart';
import 'run_audit.dart';

/// One audit row's stimulus applied to one server on one port.
typedef AuditProbe = Future<String> Function(AuditServers servers, int port);

const collectWindow = Duration(seconds: 2);
const kexTimeout = Duration(seconds: 10);
const ioTimeout = Duration(seconds: 10);

/// Builds one runnable audit row: the probe runs against both servers and
/// each listener must still serve a clean login afterwards.
AuditRow row({
  required String id,
  required String stimulus,
  required String citation,
  required String predicted,
  required AuditProbe probe,
}) {
  return AuditRow(
    id: id,
    stimulus: stimulus,
    sourceHint: citation,
    run: (servers) => runBoth(servers, id, citation, predicted, probe),
  );
}

/// Runs [probe] against both servers, then the crash-isolation check.
Future<RowResult> runBoth(
  AuditServers servers,
  String id,
  String citation,
  String predicted,
  AuditProbe probe,
) async {
  final openSshActual = await safeProbe(servers, probe, servers.sshdPort);
  final tpSshdActual = await safeProbe(servers, probe, servers.tpdPort);
  // Crash-isolation: whatever the row did, each listener must still serve
  // a clean publickey login (for tp_sshd this is the in-process survival
  // check; for sshd it is the control).
  final openSshAlive = await cleanLoginWorks(servers, servers.sshdPort);
  final tpSshdAlive = await cleanLoginWorks(servers, servers.tpdPort);
  return RowResult(
    id: id,
    expected: OpenSshExpectation(citation, predicted),
    openSshActual:
        '$openSshActual; listener alive: ${openSshAlive ? 'yes' : 'NO'}',
    tpSshdActual:
        '$tpSshdActual; listener alive: ${tpSshdAlive ? 'yes' : 'NO'}',
  );
}

/// Runs one probe, converting a crash or timeout into a recorded actual
/// instead of taking the whole audit run down with it.
Future<String> safeProbe(
  AuditServers servers,
  AuditProbe probe,
  int port,
) async {
  try {
    return await probe(servers, port).timeout(const Duration(seconds: 60));
  } on Object catch (error) {
    return 'PROBE ERROR: $error';
  }
}

/// A clean publickey login against one audit server (no session traffic).
Future<bool> cleanLoginWorks(AuditServers servers, int port) async {
  try {
    final client = SSHClient(
      await SSHSocket.connect('127.0.0.1', port),
      username: servers.username,
      identities: [deviceKey(servers)],
      onVerifyHostKey: (_, __) => true,
    );
    client.done.catchError((_) {});
    try {
      await client.authenticated.timeout(kexTimeout);
      return true;
    } finally {
      // A close on an already-reset connection completes with an error;
      // that error is not part of the row's observable.
      await client.close().catchError((_) {});
    }
  } on Object {
    return false;
  }
}

SSHKeyPair deviceKey(AuditServers servers) =>
    SSHKeyPair.fromPem(servers.deviceKeyPem).single;

Future<List<Observed>> snapshot(RawSession session) =>
    session.collect(window: Duration.zero);

/// Renders observations compactly, run-length collapsing repeats
/// (e.g. "msg:93(CHANNEL_WINDOW_ADJUST) x5").
String describe(List<Observed> observations) {
  if (observations.isEmpty) return '(no response)';
  final parts = <String>[];
  for (final observation in observations) {
    final text = observation.toString();
    if (parts.isNotEmpty && parts.last == text) {
      parts[parts.length - 1] = '$text x2';
      continue;
    }
    final match = parts.isEmpty
        ? null
        : RegExp('${RegExp.escape(text)} x(\\d+)\$').firstMatch(parts.last);
    if (match != null) {
      parts[parts.length - 1] = '$text x${int.parse(match.group(1)!) + 1}';
      continue;
    }
    parts.add(text);
  }
  return parts.join(', ');
}

/// Post-auth observations with sshd's ambient traffic (the unsolicited
/// hostkeys GLOBAL_REQUEST + DEBUG, see DIFFERENTIAL_AUDIT.md's method
/// section) filtered out — the same normalization the verdicts apply.
String describePostAuth(List<Observed> observations) => describe(
      observations
          .where(
            (o) =>
                o is! MessageObservation ||
                (o.id != SSH_Message_Global_Request.messageId &&
                    o.id != SSH_Message_Debug.messageId),
          )
          .toList(),
    );

/// The OpenSSH-side actual with the sshd DEBUG3 log cross-check appended
/// (rows whose wire observable is a bare close rely on the log to confirm
/// the source path actually taken).
Future<String> withSshdLogCheck(
  AuditServers servers,
  int port,
  String result,
  String needle,
) async {
  if (port != servers.sshdPort) return result;
  await Future<void>.delayed(const Duration(milliseconds: 300));
  try {
    final log = File(servers.sshdLogPath);
    final hit = log.existsSync() &&
        log.readAsLinesSync().any((line) => line.contains(needle));
    return '$result; sshd log: ${hit ? 'confirms "$needle"' : 'does NOT contain "$needle"'}';
  } on Object catch (error) {
    return '$result; (log read failed: $error)';
  }
}

/// [withSshdLogCheck] for rows whose teardown log line has more than one
/// plausible wording: reports the first needle found, or that none matched.
Future<String> withSshdLogCheckAny(
  AuditServers servers,
  int port,
  String result,
  List<String> needles,
) async {
  if (port != servers.sshdPort) return result;
  await Future<void>.delayed(const Duration(milliseconds: 300));
  try {
    final log = File(servers.sshdLogPath);
    if (!log.existsSync()) return '$result; sshd log: (no log)';
    final lines = log.readAsLinesSync();
    for (final needle in needles) {
      if (lines.any((line) => line.contains(needle))) {
        return '$result; sshd log: confirms "$needle"';
      }
    }
    return '$result; sshd log: none of ${needles.join(' / ')} found';
  } on Object catch (error) {
    return '$result; (log read failed: $error)';
  }
}

/// Polls until [condition] holds (or times out with a named error).
Future<void> waitUntil(
  bool Function() condition, {
  required String what,
  Duration timeout = ioTimeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Polls until a message with one of [ids] arrives after observation index
/// [since] (or times out). The `since` anchor keeps a probe that opens its
/// second channel on one connection from matching the first channel's
/// replies.
Future<void> awaitMessage(
  RawSession session,
  List<int> ids, {
  int since = 0,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final observations = await snapshot(session);
    if (observations
        .skip(since)
        .any((o) => o is MessageObservation && ids.contains(o.id))) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('message ${ids.join('/')} not observed');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Polls until [condition] holds over the observations after index [since].
Future<void> awaitObservation(
  RawSession session,
  bool Function(List<Observed> observations) condition, {
  required String what,
  int since = 0,
  Duration timeout = ioTimeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final observations = (await snapshot(session)).skip(since).toList();
    if (condition(observations)) return;
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// A logged-in dartssh2 client for the real-client probes.
Future<SSHClient> loginClient(AuditServers servers, int port) async {
  final client = SSHClient(
    await SSHSocket.connect('127.0.0.1', port),
    username: servers.username,
    identities: [deviceKey(servers)],
    onVerifyHostKey: (_, __) => true,
  );
  client.done.catchError((_) {});
  await client.authenticated.timeout(kexTimeout);
  return client;
}

/// Dials, logs in, and hands back the post-auth session plus the baseline
/// observation count (the shared prefix of the raw-transport rows).
Future<(RawSession, int)> dialPostAuth(AuditServers servers, int port) async {
  final session = await dialAuthenticated(
    port: port,
    identity: deviceKey(servers),
    username: servers.username,
  );
  try {
    await session.authenticated.timeout(kexTimeout);
    final baseline = await snapshot(session);
    return (session, baseline.length);
  } on Object {
    await session.close();
    rethrow;
  }
}

// ---------------------------------------------------------------------------
// Session-channel scaffolding (the post-auth channel rows' shared prefix)
// ---------------------------------------------------------------------------

/// Opens one `session` channel on [session] and waits for the confirmation.
///
/// The server-assigned channel id is PARSED from the confirmation's
/// senderChannel — never assumed — because every later channel message must
/// address the server by the id it chose (area C/D review rule).
Future<SSH_Message_Channel_Confirmation> openSessionChannel(
  RawSession session, {
  int senderChannel = 100,
  int clientWindow = 2 * 1024 * 1024,
  int clientMaxPacket = 32768,
  int since = 0,
}) async {
  session.transport!.sendPacket(
    SSH_Message_Channel_Open(
      channelType: 'session',
      senderChannel: senderChannel,
      initialWindowSize: clientWindow,
      maximumPacketSize: clientMaxPacket,
    ).encode(),
  );
  await awaitMessage(
    session,
    const [
      SSH_Message_Channel_Confirmation.messageId,
      SSH_Message_Channel_Open_Failure.messageId,
    ],
    since: since,
  );
  final confirmation = latestConfirmation(session, since: since);
  if (confirmation == null) {
    throw StateError('the channel open was not confirmed');
  }
  return confirmation;
}

/// The most recent CHANNEL_OPEN_CONFIRMATION after observation index
/// [since], decoded from its recorded payload, or `null` when none arrived.
SSH_Message_Channel_Confirmation? latestConfirmation(
  RawSession session, {
  int since = 0,
}) {
  final observations = session.currentObservations;
  for (final observation in observations.reversed) {
    if (observation is MessageObservation &&
        observation.id == SSH_Message_Channel_Confirmation.messageId &&
        observation.payload != null) {
      return SSH_Message_Channel_Confirmation.decode(observation.payload!);
    }
  }
  return null;
}

/// The most recent CHANNEL_OPEN (a server-initiated open, e.g.
/// `forwarded-tcpip`) after observation index [since], or `null`.
SSH_Message_Channel_Open? latestServerChannelOpen(
  RawSession session, {
  int since = 0,
}) {
  final observations = session.currentObservations;
  for (final observation in observations.reversed) {
    if (observation is MessageObservation &&
        observation.id == SSH_Message_Channel_Open.messageId &&
        observation.payload != null) {
      return SSH_Message_Channel_Open.decode(observation.payload!);
    }
  }
  return null;
}

/// Sends an `exec` request and waits for its CHANNEL_SUCCESS reply.
Future<void> requestExec(
  RawSession session,
  int serverChannel,
  String command, {
  int since = 0,
}) async {
  session.transport!.sendPacket(
    SSH_Message_Channel_Request.exec(
      recipientChannel: serverChannel,
      wantReply: true,
      command: command,
    ).encode(),
  );
  await awaitMessage(
    session,
    const [SSH_Message_Channel_Success.messageId],
    since: since,
  );
}

/// The most recent message observation with one of [ids] after observation
/// index [since], or `null` — for probes that read message-specific fields
/// out of the recorded payload (an open-failure reason, a request type).
MessageObservation? latestMessage(
  RawSession session,
  List<int> ids, {
  int since = 0,
}) {
  final observations = session.currentObservations.skip(since).toList();
  for (var i = observations.length - 1; i >= 0; i--) {
    final observation = observations[i];
    if (observation is MessageObservation && ids.contains(observation.id)) {
      return observation;
    }
  }
  return null;
}

/// Total `CHANNEL_DATA` payload bytes in [observations] — the received
/// volume of one direction, the row observable for the window rows.
int receivedDataBytes(List<Observed> observations) {
  var bytes = 0;
  for (final observation in observations) {
    if (observation is MessageObservation &&
        observation.id == SSH_Message_Channel_Data.messageId &&
        observation.payload != null) {
      try {
        bytes +=
            SSH_Message_Channel_Data.decode(observation.payload!).data.length;
      } on Object {
        // A decode failure must not mask the id-level observation.
      }
    }
  }
  return bytes;
}

/// Concatenated `CHANNEL_DATA` payloads — for byte-integrity checks.
Uint8List receivedData(List<Observed> observations) {
  final builder = BytesBuilder(copy: false);
  for (final observation in observations) {
    if (observation is MessageObservation &&
        observation.id == SSH_Message_Channel_Data.messageId &&
        observation.payload != null) {
      try {
        builder.add(SSH_Message_Channel_Data.decode(observation.payload!).data);
      } on Object {
        // Undecodable tail: the integrity check below will fail on the
        // length mismatch, which is the honest observable.
      }
    }
  }
  return builder.takeBytes();
}

bool bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
