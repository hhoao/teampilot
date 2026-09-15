/// Area E of the tp_sshd differential audit: timing-sensitive surfaces.
///
/// 6 rows (E01–E06). Every row's OpenSSH expectation was written from the
/// V_10_2_P1 source BEFORE the row ran (see DIFFERENTIAL_AUDIT.md); the
/// runners here only apply the stimulus to both servers and record what
/// came back.
///
/// Method note (the doc repeats it): timing rows are judged `match-in-kind`
/// — both servers uniform, or both variable — never by numeric equality;
/// wall-clock microseconds over loopback TCP are not comparable across
/// processes. What IS a finding is an oracle: a failure class one server
/// makes indistinguishable (by padding) that the other answers at
/// measurably different speeds.
///
/// E01/E02/E04 run on DEDICATED harness instances (see [dedicatedRow]):
/// their stimuli need sshd config the shared harness does not carry
/// (`PerSourcePenalties no`, `LoginGraceTime 3`, `MaxStartups 3:100:6`)
/// and must not poison the shared sshd's per-source penalty state for the
/// rows that follow.
///
/// VM-only tool code: `dart:io` sockets and processes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' show SSHKeyPair;
import 'package:dartssh2/protocol.dart';

import 'area_a_malformed.dart' show AuditRow;
import 'audit_harness.dart';
import 'raw_driver.dart';
import 'row_plumbing.dart';
import 'run_audit.dart';

/// The Area E rows (E01–E06).
List<AuditRow> areaERows() => [
      dedicatedRow(
        id: 'E01',
        stimulus: 'auth-failure timing distribution: 50 fresh connections per '
            'condition — wrong-key (real username, distrusted key, VALID RFC 4252 '
            '§7 signature), unknown-user (nonexistent username, otherwise valid '
            'login), malformed-blob (undecodable key blob, A10\'s shape) — '
            'wall-clock µs from the USERAUTH_REQUEST send to the USERAUTH_FAILURE '
            'reply, per cell (dedicated harness, PerSourcePenalties off: the 150 '
            'failing logins must measure auth timing, not penalty gating)',
        citation:
            'auth2.c:input_userauth_request -> ensure_minimum_time_since + '
            'user_specific_delay (every failed non-"none" attempt is PADDED: '
            '5 ms floor + 0-4.2 ms pseudorandom jitter derived per-username from '
            'timing_secret) vs server_connection.dart:_handleUserauthRequest '
            '(three distinct paths — a username mismatch fails before any crypto, '
            'a wrong key pays the full ed25519 verify + the async authenticate '
            'callback, a malformed blob fails in decode — with no '
            'failure-timing floor anywhere)',
        predicted: 'sshd: every cell ~5-9 ms (the floor plus the per-username '
            'jitter), the three conditions indistinguishable from each other — '
            'the padding is the anti-oracle; tp_sshd: unknown',
        sshdConfigExtras: const {'PerSourcePenalties': 'no'},
        probe: _probeE01,
      ),
      dedicatedRow(
        id: 'E02',
        stimulus: 'pre-auth idle timeout: dial, complete the key exchange, '
            'negotiate ssh-userauth, then send nothing — time-to-teardown and the '
            'teardown observable (both servers configured to a 3 s pre-auth '
            'timeout — sshd `LoginGraceTime 3`, tp_sshd `authTimeout 3 s` — so '
            'the row is runnable; the default-value divergence is recorded in '
            'the triage)',
        citation: 'sshd-session.c:1238-1248 (setitimer: login_grace_time PLUS '
            'arc4random_uniform(4 s) jitter) -> grace_alarm_handler '
            '(sshd-session.c:211: kill the process group + _exit(EXIT_LOGIN_GRACE), '
            'no wire DISCONNECT) vs server_connection.dart:48 Timer(authTimeout) '
            '-> _onAuthTimeout -> close()',
        predicted: 'sshd: silent close (no DISCONNECT) at 3 s + 0-4 s random '
            'jitter (so between ~3 and ~7 s from the dial); tp_sshd: silent close '
            'at exactly 3 s, no jitter',
        sshdConfigExtras: const {
          'LoginGraceTime': '3',
          'PerSourcePenalties': 'no'
        },
        tpSshdAuthTimeout: const Duration(seconds: 3),
        probe: _probeE02,
      ),
      row(
        id: 'E03',
        stimulus: 'post-auth idle: an authenticated connection left completely '
            'alone for 5 s (no traffic, no channels) — any messages from the '
            'server, and does the connection survive the idle window',
        citation: 'servconf.c:452-455 (client_alive_interval defaults to 0 = '
            'disabled; serverloop.c:client_alive_check only sends probes when the '
            'interval is > 0) vs server_connection.dart (no post-auth timer at '
            'all: the only per-connection timer, _authTimer, is cancelled the '
            'moment authentication succeeds)',
        predicted:
            'both: zero messages during the idle window, connection still '
            'open (no keepalive probes, no idle teardown on either server)',
        probe: _probeE03,
      ),
      dedicatedRow(
        id: 'E04',
        stimulus:
            'pre-auth connection flood: 7 connections opened sequentially '
            'and held open unauthenticated (dedicated harness, sshd configured '
            'MaxStartups 3:100:6 so the drop pattern is deterministic: '
            'begin=3, rate=100%, full=6); the first bytes from each connection '
            'classify it as accepted (SSH banner) or dropped',
        citation: 'sshd.c:drop_connection + should_drop_connection (startups '
            '3-5 always dropped at rate 100, >= 6 always dropped: the plaintext '
            '"Not allowed at this time\\r\\n" line is written and the socket '
            'closed before any SSH banner) vs ssh_server.dart / '
            'server_connection.dart (no pre-auth connection cap at all: every '
            'accepted connection gets its banner and its auth window)',
        predicted:
            'sshd: connections #1-3 accepted (banners), #4-7 dropped with '
            'the "Not allowed at this time" line then close; tp_sshd: 7/7 '
            'accepted, no refusal anywhere',
        sshdConfigExtras: const {'MaxStartups': '3:100:6'},
        probe: _probeE04,
      ),
      row(
        id: 'E05',
        stimulus: 'channel-cap enforcement timing (post-auth): 10 session '
            'channels confirmed, then 10 timed attempts to open the 11th — µs '
            'from each CHANNEL_OPEN send to its CHANNEL_OPEN_FAILURE reply '
            '(C08 already recorded the refusal-code divergence; this row is the '
            'enforcement-timing half)',
        citation: 'session.c:session_new (sessions_nalloc >= max_sessions -> '
            'NULL, inside the dispatch) -> serverloop.c:server_input_channel_open '
            '(immediate CHANNEL_OPEN_FAILURE, same turn) vs '
            'server_connection.dart:_handleChannelOpen (the cap check sends the '
            'failure before the type dispatch, same turn)',
        predicted: 'both refuse in-dispatch with no artificial delay '
            '(sub-millisecond on both); no deferred/rate-limited refusal',
        probe: _probeE05,
      ),
      row(
        id: 'E06',
        stimulus: 'keepalive global-request cadence: 20 rapid '
            '`keepalive@openssh.com` GLOBAL_REQUESTs with want_reply = true '
            'post-auth (pipelined, no waiting between them), then a liveness '
            'check — every request must be answered',
        citation: 'serverloop.c:server_input_global_request '
            '(keepalive@openssh.com is NOT in the known-request list — it is '
            'sshd\'s own OUTGOING keepalive name, serverloop.c:132-138; an '
            'incoming one is an unknown request -> success stays 0 -> '
            'REQUEST_FAILURE per request) + serverloop.c:402-410 '
            'server_input_keep_alive (any of the four reply types resets the '
            'alive counter) vs server_connection.dart:209-215 '
            '(keepalive@openssh.com answered REQUEST_SUCCESS when want_reply)',
        predicted: 'sshd: 20 × REQUEST_FAILURE, connection open; tp_sshd: 20 × '
            'REQUEST_SUCCESS, connection open — both answer every request '
            '(liveness-equivalent, different reply type)',
        probe: _probeE06,
      ),
    ];

// ---------------------------------------------------------------------------
// Dedicated-harness rows (E01/E02/E04)
// ---------------------------------------------------------------------------

/// A row whose stimulus needs server config the shared harness does not
/// carry: starts a dedicated [AuditServers] pair with [sshdConfigExtras] /
/// [tpSshdAuthTimeout], runs the probe + crash-isolation check against IT
/// (the same [row_plumbing.runBoth] shape), then tears it down. The shared
/// pair from `run_audit.dart` is never touched.
AuditRow dedicatedRow({
  required String id,
  required String stimulus,
  required String citation,
  required String predicted,
  Map<String, String> sshdConfigExtras = const {},
  Duration? tpSshdAuthTimeout,
  required AuditProbe probe,
}) {
  return AuditRow(
    id: id,
    stimulus: stimulus,
    sourceHint: citation,
    run: (_) async {
      final AuditServers dedicated;
      try {
        dedicated = await startAuditServers(
          sshdConfigExtras: sshdConfigExtras,
          tpSshdAuthTimeout: tpSshdAuthTimeout,
        );
      } on Object catch (error) {
        return RowResult(
          id: id,
          expected: OpenSshExpectation(citation, predicted),
          openSshActual: 'HARNESS ERROR: $error',
          tpSshdActual: 'HARNESS ERROR: $error',
        );
      }
      try {
        return await runBoth(dedicated, id, citation, predicted, probe);
      } finally {
        await dedicated.close();
      }
    },
  );
}

// ---------------------------------------------------------------------------
// E01 — auth-failure timing distribution
// ---------------------------------------------------------------------------

/// Trials per condition per server for E01 (the audit plan's N=50).
const e01Trials = 50;

/// A private key neither server authorizes — the wrong-key condition signs
/// with it (a VALID signature of an untrusted key, unlike Area A's A11
/// which corrupted the signature of the trusted key).
const _distrustedKeyPem = '''
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACBLkEYvC2z4l86FQ4iqolEJ0iioLiL+gl0Lh3HC/5l44gAAALA1CdTENQnU
xAAAAAtzc2gtZWQyNTUxOQAAACBLkEYvC2z4l86FQ4iqolEJ0iioLiL+gl0Lh3HC/5l44g
AAAEC1MDoCBEbMGyjATdGZB1/Jg0ihk/bh8/bRxpW2m0IK6EuQRi8LbPiXzoVDiKqiUQnS
KKguIv6CXQuHccL/mXjiAAAAJnRwLXNzaGQtZGlmZmVyZW50aWFsLWFyZWEtZS1kaXN0cn
VzdGVkAQIDBAUGBw==
-----END OPENSSH PRIVATE KEY-----
''';

final _distrustedKey = SSHKeyPair.fromPem(_distrustedKeyPem).single;

/// E01's three failure conditions (label doubles as the doc-cell name).
enum _FailureCondition {
  wrongKey('wrong-key'),
  unknownUser('unknown-user'),
  malformedBlob('malformed-blob');

  const _FailureCondition(this.label);
  final String label;
}

Future<String> _probeE01(AuditServers servers, int port) async {
  final cells = <String>[];
  for (final condition in _FailureCondition.values) {
    final samples = <int>[];
    for (var i = 0; i < e01Trials; i++) {
      samples.add(await _timedAuthFailure(servers, port, condition));
    }
    samples.sort();
    cells.add('${condition.label}: ${_timingStats(samples)}');
  }
  return cells.join('; ');
}

/// One fresh connection per trial: both servers cap failed attempts at 6
/// (A12), so reusing a connection would measure the cap, not the timing.
Future<int> _timedAuthFailure(
  AuditServers servers,
  int port,
  _FailureCondition condition,
) async {
  final session = await dialPostKex(port: port);
  try {
    await session.keyExchangeDone.timeout(kexTimeout);
    await _negotiateUserService(session);
    final since = (await snapshot(session)).length;
    final request = switch (condition) {
      // Real username, distrusted key, VALID RFC 4252 §7 signature.
      _FailureCondition.wrongKey => _signedWrongKeyRequest(servers, session),
      // A username neither server knows; everything else a valid login.
      _FailureCondition.unknownUser => _signedWrongKeyRequest(
          servers,
          session,
          username: 'tp-diff-no-such-user',
        ),
      // A10's undecodable blob: no decoder can read a key out of it.
      _FailureCondition.malformedBlob => SSH_Message_Userauth_Request.publicKey(
          username: servers.username,
          publicKeyAlgorithm: 'ssh-ed25519',
          publicKey: Uint8List.fromList([0, 0, 0, 3, 1, 2, 3]),
          signature: null,
        ),
    };
    final sentAt = observationClockMicros();
    session.transport!.sendPacket(request.encode());
    await awaitMessage(
      session,
      const [
        SSH_Message_Userauth_Failure.messageId,
        SSH_Message_Disconnect.messageId,
        SSH_Message_Userauth_Success.messageId,
      ],
      since: since,
    );
    final failure = latestMessage(
      session,
      const [SSH_Message_Userauth_Failure.messageId],
      since: since,
    );
    if (failure == null) {
      throw StateError(
        'no USERAUTH_FAILURE for condition ${condition.label}',
      );
    }
    return failure.timestamp - sentAt;
  } finally {
    await session.close();
  }
}

/// A signed publickey request the way `dialAuthenticated` composes it, but
/// for the distrusted key (or the real device key under a bogus username).
SSH_Message_Userauth_Request _signedWrongKeyRequest(
  AuditServers servers,
  RawSession session, {
  String? username,
}) {
  final identity = username == null ? _distrustedKey : deviceKey(servers);
  final publicKey = identity.toPublicKey().encode();
  final transport = session.transport!;
  final challenge = transport.composeChallenge(
    username: username ?? servers.username,
    service: 'ssh-connection',
    publicKeyAlgorithm: 'ssh-ed25519',
    publicKey: publicKey,
  );
  return SSH_Message_Userauth_Request.publicKey(
    username: username ?? servers.username,
    publicKeyAlgorithm: 'ssh-ed25519',
    publicKey: publicKey,
    signature: identity.sign(challenge).encode(),
  );
}

/// Sends the ssh-userauth SERVICE_REQUEST and waits for the SERVICE_ACCEPT.
Future<void> _negotiateUserService(RawSession session) async {
  final since = (await snapshot(session)).length;
  session.transport!.sendPacket(
    SSH_Message_Service_Request('ssh-userauth').encode(),
  );
  await awaitMessage(
    session,
    const [SSH_Message_Service_Accept.messageId],
    since: since,
  );
}

// ---------------------------------------------------------------------------
// E02 — pre-auth idle timeout
// ---------------------------------------------------------------------------

Future<String> _probeE02(AuditServers servers, int port) async {
  final session = await dialPostKex(port: port);
  try {
    await session.keyExchangeDone.timeout(kexTimeout);
    await _negotiateUserService(session);
    final since = (await snapshot(session)).length;
    final start = observationClockMicros();
    await awaitObservation(
      session,
      (observations) => observations.isNotEmpty,
      what: 'the pre-auth idle teardown',
      since: since,
      timeout: const Duration(seconds: 15),
    );
    final observations = (await snapshot(session)).skip(since).toList();
    final teardownAt = (observations.last.timestamp - start) / 1000000;
    return 'idle teardown after ${teardownAt.toStringAsFixed(2)} s: '
        '${describe(observations)}';
  } finally {
    await session.close();
  }
}

// ---------------------------------------------------------------------------
// E03 — post-auth idle
// ---------------------------------------------------------------------------

Future<String> _probeE03(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    final observations = await session.collect(
      window: const Duration(seconds: 5),
    );
    final idle = observations.skip(baseline).toList();
    final closed = idle.any(
      (observation) =>
          observation is ClosedObservation ||
          observation is DisconnectObservation,
    );
    final traffic = describePostAuth(idle);
    if (traffic == '(no response)') {
      return 'no keepalive probes or other traffic during a 5 s idle'
          '${idle.isEmpty ? '' : ' (${idle.length} ambient message(s) filtered)'}, '
          'connection open';
    }
    return '$traffic; connection ${closed ? 'CLOSED' : 'open'}';
  } finally {
    await session.close();
  }
}

// ---------------------------------------------------------------------------
// E04 — pre-auth connection flood (MaxStartups)
// ---------------------------------------------------------------------------

const e04Connections = 7;

/// One classified pre-auth connection of the E04 flood: its first bytes
/// (an accepted connection's SSH banner, or the MaxStartups refusal line)
/// and whether the socket went away after them.
class _FloodConnection {
  _FloodConnection(this.firstBytes, this.closedAfterFirstBytes);

  final String firstBytes;
  final bool closedAfterFirstBytes;
}

/// Dials [port] and classifies the connection by its first bytes, holding
/// the socket open (each accepted connection must keep occupying its
/// pre-auth slot). The subscription stays active so a post-first-bytes
/// close by the server is observable.
Future<(_FloodConnection, Socket)> _dialAndClassify(int port) async {
  final socket = await Socket.connect('127.0.0.1', port);
  final firstBytes = Completer<Uint8List>();
  final closed = Completer<void>();
  final subscription = socket.listen(
    (data) {
      if (!firstBytes.isCompleted) firstBytes.complete(data);
    },
    onError: (Object error) {
      if (!firstBytes.isCompleted) firstBytes.completeError(error);
      if (!closed.isCompleted) closed.complete();
    },
    onDone: () {
      if (!firstBytes.isCompleted) {
        firstBytes.completeError(StateError('closed before any bytes'));
      }
      if (!closed.isCompleted) closed.complete();
    },
  );
  try {
    final bytes = await firstBytes.future.timeout(ioTimeout);
    var closedAfter = false;
    try {
      await closed.future.timeout(const Duration(seconds: 2));
      closedAfter = true;
    } on Object {
      // Still open after 2 s: recorded as the finding it is.
    }
    return (
      _FloodConnection(utf8.decode(bytes).trim(), closedAfter),
      socket,
    );
  } finally {
    await subscription.cancel();
  }
}

Future<String> _probeE04(AuditServers servers, int port) async {
  final sockets = <Socket>[];
  try {
    final accepted = <int>[];
    final dropped = <int>[];
    final anomalies = <String>[];
    for (var i = 1; i <= e04Connections; i++) {
      final (connection, socket) = await _dialAndClassify(port);
      sockets.add(socket);
      if (connection.firstBytes.startsWith('SSH-')) {
        accepted.add(i);
      } else if (connection.firstBytes.startsWith('Not allowed')) {
        dropped.add(i);
        if (!connection.closedAfterFirstBytes) {
          anomalies.add('connection #$i refused but NOT closed');
        }
      } else {
        anomalies.add('connection #$i first bytes: '
            '"${connection.firstBytes}"');
      }
    }
    final result =
        'accepted #${accepted.isEmpty ? '(none)' : accepted.join(', #')}, '
        'dropped #${dropped.isEmpty ? '(none)' : dropped.join(', #')} '
        '(of $e04Connections)'
        '${anomalies.isEmpty ? '' : '; ${anomalies.join('; ')}'}';
    return await withSshdLogCheck(servers, port, result, 'drop connection');
  } finally {
    for (final socket in sockets) {
      socket.destroy();
    }
  }
}

// ---------------------------------------------------------------------------
// E05 — channel-cap enforcement timing
// ---------------------------------------------------------------------------

const e05CapOpens = 10;

Future<String> _probeE05(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    // Phase 1: fill the per-connection channel cap (both servers: 10).
    var since = 0;
    var confirmed = 0;
    String? firstRefusal;
    for (var i = 0; i <= e05CapOpens; i++) {
      since = (await snapshot(session)).length;
      session.transport!.sendPacket(
        SSH_Message_Channel_Open(
          channelType: 'session',
          senderChannel: 300 + i,
          initialWindowSize: 2 * 1024 * 1024,
          maximumPacketSize: 32768,
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
      final reply = latestMessage(
        session,
        const [
          SSH_Message_Channel_Confirmation.messageId,
          SSH_Message_Channel_Open_Failure.messageId,
        ],
        since: since,
      );
      if (reply?.id == SSH_Message_Channel_Confirmation.messageId) {
        confirmed++;
        continue;
      }
      if (reply?.payload != null) {
        final failure = SSH_Message_Channel_Open_Failure.decode(
          reply!.payload!,
        );
        firstRefusal = 'reason=${failure.reasonCode} "${failure.description}"';
        break;
      }
      throw StateError('open #${i + 1} was neither confirmed nor refused');
    }
    since = (await snapshot(session)).length;

    // Phase 2: 10 timed attempts at the capped 11th open — the refusal's
    // enforcement latency is the row's observable.
    final samples = <int>[];
    for (var i = 0; i < 10; i++) {
      final sentAt = observationClockMicros();
      session.transport!.sendPacket(
        SSH_Message_Channel_Open(
          channelType: 'session',
          senderChannel: 400 + i,
          initialWindowSize: 2 * 1024 * 1024,
          maximumPacketSize: 32768,
        ).encode(),
      );
      await awaitMessage(
        session,
        const [SSH_Message_Channel_Open_Failure.messageId],
        since: since,
      );
      final failure = latestMessage(
        session,
        const [SSH_Message_Channel_Open_Failure.messageId],
        since: since,
      );
      if (failure == null) {
        throw StateError('the capped 11th open was not refused');
      }
      samples.add(failure.timestamp - sentAt);
      since = (await snapshot(session)).length;
    }
    samples.sort();
    return '$confirmed/${e05CapOpens + 1} opens confirmed, then 10 capped '
        'opens refused ($firstRefusal) in ${_timingStats(samples)}';
  } finally {
    await session.close();
  }
}

// ---------------------------------------------------------------------------
// E06 — keepalive global-request cadence
// ---------------------------------------------------------------------------

const e06Keepalives = 20;

Future<String> _probeE06(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    final since = (await snapshot(session)).length;
    for (var i = 0; i < e06Keepalives; i++) {
      session.transport!.sendPacket(
        SSH_Message_Global_Request(
          requestName: 'keepalive@openssh.com',
          wantReply: true,
        ).encode(),
      );
    }
    await awaitObservation(
      session,
      (observations) =>
          observations
              .where(
                (observation) =>
                    observation is MessageObservation &&
                    (observation.id == SSH_Message_Request_Success.messageId ||
                        observation.id ==
                            SSH_Message_Request_Failure.messageId),
              )
              .length >=
          e06Keepalives,
      what: '$e06Keepalives keepalive replies',
    );
    final replies = (await snapshot(session))
        .skip(since)
        .whereType<MessageObservation>()
        .where(
          (observation) =>
              observation.id == SSH_Message_Request_Success.messageId ||
              observation.id == SSH_Message_Request_Failure.messageId,
        )
        .toList();
    final successes = replies
        .where(
          (observation) =>
              observation.id == SSH_Message_Request_Success.messageId,
        )
        .length;
    final failures = replies.length - successes;
    final stillOpen = !(await snapshot(session))
        .skip(since)
        .any((observation) => observation is! MessageObservation);
    return '$e06Keepalives pipelined keepalive@openssh.com GLOBAL_REQUESTs '
        '-> ${successes} × REQUEST_SUCCESS, ${failures} × REQUEST_FAILURE, '
        'connection ${stillOpen ? 'open' : 'CLOSED'}';
  } finally {
    await session.close();
  }
}

// ---------------------------------------------------------------------------
// Timing stats shared by E01/E05
// ---------------------------------------------------------------------------

/// Median / p95 / max of sorted microsecond samples — the timing rows'
/// doc-cell format. Never a cross-server numeric comparison (method note).
String _timingStats(List<int> sortedMicros) {
  if (sortedMicros.isEmpty) return '(no samples)';
  int percentile(int p) => sortedMicros[(sortedMicros.length - 1) * p ~/ 100];
  return 'med ${percentile(50)}µs '
      'p95 ${percentile(95)}µs '
      'max ${sortedMicros.last}µs';
}
