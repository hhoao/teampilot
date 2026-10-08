/// Area B of the tp_sshd differential audit: rekey timing.
///
/// 8 rows (B01–B08). Every runnable row's OpenSSH expectation was written
/// from the V_10_2_P1 source BEFORE the row ran (see DIFFERENTIAL_AUDIT.md);
/// the runners here only apply the stimulus to both servers and record what
/// came back. Anchor finding (pre-confirmed): tp_sshd NEVER initiates a
/// rekey — dartssh2's `rekey()` (ssh_transport.dart:2054) is a client-role
/// API, and tp_sshd's server wiring has no byte counter and no timer — so
/// every runnable row drives the exchange from the client side, which is
/// also the only way a real peer can rotate keys against tp_sshd.
///
/// B05 (host key change on rekey) is a client-policy reference row and
/// B06/B07 (byte/time rekey thresholds) are documentation rows: none is
/// differentially runnable without a MITM proxy or a multi-hour/multi-GB
/// session, so they are recorded from source only.
///
/// VM-only tool code: `dart:io` sockets and processes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' show SSHClient, SSHKeyPair, SSHSocket;
import 'package:dartssh2/protocol.dart';

import 'area_a_malformed.dart' show AuditRow;
import 'audit_harness.dart';
import 'raw_driver.dart';
import 'run_audit.dart';

/// The Area B rows (B01–B08).
List<AuditRow> areaBRows() => [
  _row(
    id: 'B01',
    stimulus: 'peer-initiated rekey mid-session: a real dartssh2 SSHClient '
        'with an open exec channel (`cat`) calls rekey() between two stdin '
        'echo round-trips, then runs one more exec after the exchange',
    citation: 'kex.c:kex_send_newkeys (kex_reset_dispatch + NEWKEYS, '
        're-registers KEXINIT for the next round); kex.c:kex_input_kexinit '
        '(rekey initiation); packet.c:ssh_packet_send2 (non-KEX outgoing '
        'queued while rekeying)',
    predicted: 'a client KEXINIT after auth is a normal rekey: the server '
        'answers with its own KEXINIT, the exchange runs to NEWKEYS, and '
        'open channels keep working on the new keys',
    probe: _probeB01,
  ),
  _row(
    id: 'B02',
    stimulus: 'rekey with data in flight (x5 rounds): a 1 MiB exec stream '
        '(`head -c 1048576 <pattern file>`) is flowing when the client calls '
        'rekey() at >= 64 KiB received; the full stream must arrive '
        'byte-for-byte intact and the channel must finish (the teardown '
        'racing the exchange window is the fragile part, so the observable '
        'is the distribution over 5 rounds)',
    citation: 'packet.c:ssh_packet_send2 ("During rekeying we can only send '
        'key exchange messages. Queue everything else." — the outgoing '
        'queue, drained after NEWKEYS) vs dartssh2 ssh_transport.dart '
        '_rekeyPendingPackets (same queueing, ssh_transport.dart:383-385 '
        'and the flush in _handleMessageNewKeys)',
    predicted: 'both servers queue outgoing non-KEX packets during the '
        'exchange and drain them in order after NEWKEYS: the stream pauses '
        'briefly, then continues with no loss and no reordering',
    probe: _probeB02,
  ),
  _row(
    id: 'B03',
    stimulus: 'a SECOND client KEXINIT injected while the rekey exchange it '
        'just started is still in progress (before NEWKEYS), proposing the '
        'same algorithms',
    citation: 'kex.c:kex_input_kexinit:621 (on the first KEXINIT the server '
        're-registers KEXINIT -> kex_protocol_error for the duration of the '
        'exchange) + kex.c:kex_protocol_error:234-247 (the fatal strict '
        'branch requires KEX_INITIAL, which kex.c:kex_input_newkeys:561 '
        'clears after the first exchange, so a rekey gets the '
        'UNIMPLEMENTED branch)',
    predicted: 'the duplicate KEXINIT is not re-negotiated: it draws '
        'SSH_MSG_UNIMPLEMENTED while the in-flight exchange (started by the '
        'first KEXINIT) runs to completion; the connection continues',
    probe: _probeB03,
  ),
  _row(
    id: 'B04',
    stimulus: 'a rekey KEXINIT proposing ONLY an unsupported kex algorithm '
        '(kex list = "tp-sshd-audit-bogus-kex", everything else valid), '
        'sent post-auth',
    citation: 'kex.c:kex_input_kexinit -> kex.c:kex_choose_conf:980-984 '
        '(choose_kex fails, failed_choice = the peer kex list) -> '
        'dispatch.c:ssh_dispatch_run_fatal -> packet.c:sshpkt_vfatal '
        '(SSH_ERR_NO_KEX_ALG_MATCH + failed_choice -> logdie "Unable to '
        'negotiate ... Their offer: ...")',
    predicted: 'the server sends its own KEXINIT first (kex_input_kexinit '
        'replies before negotiating), then the negotiation failure is '
        'fatal: sshd exits via logdie — a close with NO DISCONNECT on the '
        'wire, reason only in the sshd log',
    probe: _probeB04,
  ),
  _sourceOnlyRow(
    id: 'B05',
    stimulus: 'host key change on rekey: the server presents a different '
        'host key mid-rekey — client-side policy mirror, recorded as a '
        'client-behavior reference (not differentially runnable without a '
        'MITM proxy that owns a second host key)',
    citation: 'kexgen.c:167 (kex_verify_host_key on every exchange) -> '
        'kex.c:kex_verify_host_key:1183-1196 -> sshconnect2.c:'
        'verify_host_key_callback:94-103 (fatal "Host key verification '
        'failed.")',
    predicted: 'the OpenSSH client re-verifies the server host key on every '
        'rekey; a changed key is fatal for the session',
    openSshActual: 'source-only — the client verifies the host key in every '
        'exchange (kexgen.c:167 -> kex.c:1183-1196 -> sshconnect2.c:94-103 '
        'verify_host_key_callback -> fatal "Host key verification failed.")',
    tpSshdActual: 'source-only — the dartssh2 client does the same: '
        'ssh_transport.dart:1903-1913 re-checks the fingerprint of the '
        'already-accepted host key on every rekey and closes with '
        'SSHHostkeyError "Host key changed during rekey: ..." '
        '(onVerifyHostKey is deliberately not consulted again)',
  ),
  _sourceOnlyRow(
    id: 'B06',
    stimulus: 'long-lived session byte threshold: whether the SERVER itself '
        'ever starts a rekey — source-only row (the default bound is '
        'cipher-geometry-sized, hours of loopback pumping; not run '
        'differentially)',
    citation: 'sshd_config.5:1788-1812 (RekeyLimit default "default none" — '
        'rekey after the cipher default amount of data, no time limit); '
        'servconf.c:398-401 (rekey_limit=0, rekey_interval=0); packet.c:'
        '1046-1063 (max_blocks = 2^(block_size*2), 1 GiB for 8-byte-block '
        'ciphers; MINIMUM with RekeyLimit); packet.c:1070-1123 '
        '(ssh_packet_need_rekeying / ssh_packet_check_rekey) + packet.c:'
        '1366-1399 (ssh_packet_send2 -> kex_start_rekex) — the always-armed '
        'trigger; serverloop.c:385-387 (check_rekey from the server loop)',
    predicted: 'sshd always has an armed rekey trigger: once the session '
        'exceeds the negotiated cipher\'s block bound (or a configured '
        'RekeyLimit, or 2^31 packets), the server itself sends KEXINIT '
        '(kex_start_rekex), queueing non-KEX outgoing packets until NEWKEYS',
    openSshActual: 'source-only — mechanism present and always armed: '
        'max_blocks from cipher geometry (packet.c:1046-1063), checked on '
        'every send (packet.c:1374) and from the server loop '
        '(serverloop.c:385-387); the 10.2 default is byte-bound-only '
        '(RekeyLimit "default none", servconf.c:398-401)',
    tpSshdActual: 'source-only — no trigger of any kind: server_connection'
        '.dart has neither a byte counter nor a rekey timer (zero '
        '"rekey" references), and dartssh2 rekey() (ssh_transport.dart:'
        '2054) is a client-role API no server code calls; keys rotate only '
        'if the peer asks',
  ),
  _sourceOnlyRow(
    id: 'B07',
    stimulus: 'time-based rekey (sshd hourly): source-only row — cannot '
        'practically wait an hour, and the 10.2 default has no interval at '
        'all',
    citation: 'serverloop.c:171 (the rekey deadline is only scheduled when '
        'options.rekey_interval > 0) + packet.c:1095-1097 (the interval '
        'fires) vs servconf.c:400-401 (default rekey_interval = 0)',
    predicted: 'time-based rekey fires only when RekeyLimit is configured '
        'with an interval; with the 10.2 default ("default none") sshd '
        'never time-rekeys',
    openSshActual: 'source-only — time-based rekey is configurable '
        '(RekeyLimit <bytes> <interval>) but off by default: '
        'serverloop.c:171 schedules the deadline only when '
        'rekey_interval > 0, and the default is 0 (servconf.c:400-401)',
    tpSshdActual: 'source-only — same absence as B06: no timer exists '
        'anywhere in the server wiring, so a configured-interval '
        'equivalent could not fire either',
  ),
  _row(
    id: 'B08',
    stimulus: 'strict-kex rekey variant — a NEWKEYS ordering violation '
        'during a REKEY (not the first KEX): right after the client\'s '
        'rekey KEXINIT, an out-of-order SSH_MSG_NEWKEYS is injected while '
        'the exchange is in progress (strict kex is negotiated — the '
        'dartssh2 client advertises kex-strict-c-v00@openssh.com)',
    citation: 'packet.c:1804-1808 (the read layer resets p_read.seqnr on '
        'EVERY received NEWKEYS under kex_strict — rekeys included) + '
        'kex.c:kex_input_newkeys:531 (outside an exchange NEWKEYS is '
        'dispatched to kex_protocol_error, so mid-rekey it draws '
        'UNIMPLEMENTED) + packet.c:1697/1717 (the client\'s next packet '
        'then fails its MAC: "Corrupted MAC on input.") -> packet.c:'
        'sshpkt_vfatal (teardown without a wire DISCONNECT)',
    predicted: 'the stray NEWKEYS is not applied (kex_protocol_error -> '
        'UNIMPLEMENTED) but the strict sequence-number reset still fires on '
        'receipt, so the client\'s next packet fails its MAC: sshd logs '
        '"Corrupted MAC on input." and tears the connection down — no '
        'DISCONNECT on the wire',
    probe: _probeB08,
  ),
];

// ---------------------------------------------------------------------------
// Row plumbing (mirrors area_a_malformed.dart; kept local so the completed
// Area A file stays untouched)
// ---------------------------------------------------------------------------

typedef _Probe = Future<String> Function(AuditServers servers, int port);

const _collectWindow = Duration(seconds: 2);
const _kexTimeout = Duration(seconds: 10);
const _ioTimeout = Duration(seconds: 10);
const _rekeyTimeout = Duration(seconds: 10);

AuditRow _row({
  required String id,
  required String stimulus,
  required String citation,
  required String predicted,
  required _Probe probe,
}) {
  return AuditRow(
    id: id,
    stimulus: stimulus,
    sourceHint: citation,
    run: (servers) => _runBoth(servers, id, citation, predicted, probe),
  );
}

/// A row whose observable is a source fact, not a wire behavior (B05–B07):
/// the runner reports the recorded source actuals instead of probing.
AuditRow _sourceOnlyRow({
  required String id,
  required String stimulus,
  required String citation,
  required String predicted,
  required String openSshActual,
  required String tpSshdActual,
}) {
  return AuditRow(
    id: id,
    stimulus: stimulus,
    sourceHint: citation,
    run: (_) async => RowResult(
      id: id,
      expected: OpenSshExpectation(citation, predicted),
      openSshActual: openSshActual,
      tpSshdActual: tpSshdActual,
    ),
  );
}

Future<RowResult> _runBoth(
  AuditServers servers,
  String id,
  String citation,
  String predicted,
  _Probe probe,
) async {
  final openSshActual = await _safeProbe(servers, probe, servers.sshdPort);
  final tpSshdActual = await _safeProbe(servers, probe, servers.tpdPort);
  // Crash-isolation: whatever the row did, each listener must still serve
  // a clean publickey login.
  final openSshAlive = await _cleanLoginWorks(servers, servers.sshdPort);
  final tpSshdAlive = await _cleanLoginWorks(servers, servers.tpdPort);
  return RowResult(
    id: id,
    expected: OpenSshExpectation(citation, predicted),
    openSshActual:
        '$openSshActual; listener alive: ${openSshAlive ? 'yes' : 'NO'}',
    tpSshdActual: '$tpSshdActual; listener alive: ${tpSshdAlive ? 'yes' : 'NO'}',
  );
}

Future<String> _safeProbe(
  AuditServers servers,
  _Probe probe,
  int port,
) async {
  try {
    return await probe(servers, port).timeout(const Duration(seconds: 40));
  } on Object catch (error) {
    return 'PROBE ERROR: $error';
  }
}

Future<bool> _cleanLoginWorks(AuditServers servers, int port) async {
  try {
    final identity = SSHKeyPair.fromPem(servers.deviceKeyPem).single;
    final client = SSHClient(
      await SSHSocket.connect('127.0.0.1', port),
      username: servers.username,
      identities: [identity],
      onVerifyHostKey: (_, __) => true,
    );
    client.done.catchError((_) {});
    try {
      await client.authenticated.timeout(_kexTimeout);
      return true;
    } finally {
      await client.close().catchError((_) {});
    }
  } on Object {
    return false;
  }
}

Future<List<Observed>> _snapshot(RawSession session) =>
    session.collect(window: Duration.zero);

String _describe(List<Observed> observations) {
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
String _describePostAuth(List<Observed> observations) => _describe(
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
Future<String> _withSshdLogCheck(
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

SSHKeyPair _deviceKey(AuditServers servers) =>
    SSHKeyPair.fromPem(servers.deviceKeyPem).single;

/// Polls until [condition] holds (or times out with a named error).
Future<void> _waitUntil(
  bool Function() condition, {
  required String what,
  Duration timeout = _ioTimeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

// ---------------------------------------------------------------------------
// B01/B02: real SSHClient probes (channel continuity across the rekey)
// ---------------------------------------------------------------------------

Future<SSHClient> _loginClient(AuditServers servers, int port) async {
  final client = SSHClient(
    await SSHSocket.connect('127.0.0.1', port),
    username: servers.username,
    identities: [_deviceKey(servers)],
    onVerifyHostKey: (_, __) => true,
  );
  client.done.catchError((_) {});
  await client.authenticated.timeout(_kexTimeout);
  return client;
}

Future<String> _probeB01(AuditServers servers, int port) async {
  final client = await _loginClient(servers, port);
  try {
    final session = await client.execute('cat').timeout(_ioTimeout);
    final received = StringBuffer();
    final subscription = session.stdout.listen(
      (chunk) => received.write(latin1.decode(chunk)),
    );
    try {
      Future<void> echoRoundTrip(String marker) async {
        session.stdin.add(latin1.encode('$marker\n'));
        await _waitUntil(
          () => received.toString().contains(marker),
          what: 'echo of "$marker"',
        );
      }

      await echoRoundTrip('before-rekey');
      await client.rekey().timeout(_rekeyTimeout);
      await echoRoundTrip('after-rekey');

      final post = latin1
          .decode(
            await client.run('echo post', stderr: false).timeout(_ioTimeout),
          )
          .trim();
      await session.stdin.close();
      await session.done.timeout(_ioTimeout);
      return 'rekey completed; channel echo before/after rekey ok; '
          'post-rekey exec "echo post" -> "$post"; channel closed cleanly '
          '(exit ${session.exitCode})';
    } finally {
      await subscription.cancel();
    }
  } finally {
    await client.close().catchError((_) {});
  }
}

/// The deterministic 1 MiB stream B02 pumps: 256-byte blocks, each headed by
/// its little-endian block index, so any loss or reorder is detectable.
Uint8List _b02Pattern() {
  const blockSize = 256;
  final data = Uint8List(_b02StreamBytes);
  for (var block = 0; block < _b02StreamBytes ~/ blockSize; block++) {
    final offset = block * blockSize;
    ByteData.sublistView(data, offset, offset + 8)
        .setUint64(0, block, Endian.little);
    for (var i = 8; i < blockSize; i++) {
      data[offset + i] = (block * 31 + i) & 0xff;
    }
  }
  return data;
}

const _b02StreamBytes = 1 << 20; // 1 MiB

/// How many B02 rounds run per server. Whether the channel teardown races
/// into the rekey window is a sub-millisecond timing question, so one round
/// is one coin flip; five rounds make the row's observable the distribution
/// instead of a single coin's outcome.
const _b02Rounds = 5;

Future<String> _probeB02(AuditServers servers, int port) async {
  final pattern = _b02Pattern();
  final streamFile = File('${servers.tempDir.path}/b02_stream.bin');
  if (!streamFile.existsSync()) {
    streamFile.writeAsBytesSync(pattern);
  }
  final failures = <String>[];
  for (var round = 0; round < _b02Rounds; round++) {
    final failure = await _b02Round(servers, port, streamFile.path, pattern);
    if (failure != null) failures.add('round ${round + 1}: $failure');
  }
  if (failures.isEmpty) {
    return '$_b02Rounds/$_b02Rounds rounds: stream intact '
        '(byte-for-byte, in order), channel closed cleanly (exit 0)';
  }
  return '${_b02Rounds - failures.length}/$_b02Rounds rounds clean; '
      '${failures.join('; ')}';
}

/// One B02 round: stream 1 MiB through an exec channel, rekey at >= 64 KiB
/// in flight, then check integrity AND that the channel actually finished.
///
/// Returns `null` when everything worked, or a short description of the
/// failure (the row's observable: a hung channel or corrupted stream).
Future<String?> _b02Round(
  AuditServers servers,
  int port,
  String streamPath,
  Uint8List pattern,
) async {
  final client = await _loginClient(servers, port);
  try {
    final session = await client
        .execute('head -c $_b02StreamBytes $streamPath')
        .timeout(_ioTimeout);
    final received = BytesBuilder(copy: false);
    final subscription = session.stdout.listen(received.add);
    try {
      // Let the stream actually be in flight before the rekey starts.
      await _waitUntil(
        () => received.length >= 65536,
        what: '64 KiB of the exec stream',
      );
      await client.rekey().timeout(_rekeyTimeout);
      // The channel completing (exit-status/EOF/CLOSE from the server) is
      // itself part of the observable: teardown packets that race into the
      // exchange window are the rekey's most fragile traffic.
      var channelClosed = false;
      try {
        await session.done.timeout(const Duration(seconds: 5));
        channelClosed = true;
      } on TimeoutException {
        channelClosed = false;
      }
      final data = received.takeBytes();
      if (!_bytesEqual(data, pattern)) {
        return 'stream corrupted (${data.length}/$_b02StreamBytes bytes)';
      }
      if (!channelClosed) {
        return 'stream intact but the channel NEVER closed: the exec '
            'teardown (exit-status/EOF/CLOSE) raced into the exchange '
            'window and was dropped — the session hangs';
      }
      return null;
    } finally {
      await subscription.cancel();
    }
  } finally {
    await client.close().catchError((_) {});
  }
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// B03/B04/B08: raw transport probes (crafted packets around a rekey)
// ---------------------------------------------------------------------------

/// A well-formed KEXINIT proposing exactly the algorithms both servers
/// accept (no strict-kex marker: that is first-KEX-only signalling).
SSH_Message_KexInit _validClientKexInit() => SSH_Message_KexInit(
  kexAlgorithms: const ['curve25519-sha256'],
  serverHostKeyAlgorithms: const ['ssh-ed25519'],
  encryptionClientToServer: const [
    'aes256-ctr',
    'aes128-ctr',
    'chacha20-poly1305@openssh.com',
  ],
  encryptionServerToClient: const [
    'aes256-ctr',
    'aes128-ctr',
    'chacha20-poly1305@openssh.com',
  ],
  macClientToServer: const [
    'hmac-sha2-256-etm@openssh.com',
    'hmac-sha2-256',
  ],
  macServerToClient: const [
    'hmac-sha2-256-etm@openssh.com',
    'hmac-sha2-256',
  ],
  compressionClientToServer: const ['none'],
  compressionServerToClient: const ['none'],
  firstKexPacketFollows: false,
);

/// Dials, logs in, and hands back the post-auth session plus the baseline
/// observation count (the shared prefix of the raw-transport rows).
Future<(RawSession, int)> _dialPostAuth(AuditServers servers, int port) async {
  final session = await dialAuthenticated(
    port: port,
    identity: _deviceKey(servers),
    username: servers.username,
  );
  try {
    await session.authenticated.timeout(_kexTimeout);
    final baseline = await _snapshot(session);
    return (session, baseline.length);
  } on Object {
    await session.close();
    rethrow;
  }
}

Future<String> _probeB03(AuditServers servers, int port) async {
  final (session, baseline) = await _dialPostAuth(servers, port);
  try {
    // Start a client-initiated rekey; our KEXINIT goes out immediately.
    unawaited(session.transport!.rekey());
    // The stimulus: a SECOND KEXINIT while that exchange is in flight.
    session.transport!.sendPacket(  _validClientKexInit().encode());
    await Future<void>.delayed(const Duration(milliseconds: 500));
    // Liveness proof once the exchange settles: a want_reply global
    // request must still be answered (REQUEST_FAILURE).
    try {
      session.transport!.sendPacket(
        SSH_Message_Global_Request(
          requestName: 'audit-bogus@tp-sshd-differential',
          wantReply: true,
        ).encode(),
      );
    } on Object {
      // The transport was torn down by the row itself.
    }
    final observations = await session.collect(window: _collectWindow);
    final actual = _describePostAuth(
      observations.skip(baseline).toList(),
    );
    return await _withSshdLogCheck(
      servers,
      port,
      actual,
      'kex_protocol_error',
    );
  } finally {
    await session.close();
  }
}

Future<String> _probeB04(AuditServers servers, int port) async {
  final (session, baseline) = await _dialPostAuth(servers, port);
  try {
    // Only the kex name-list is bogus; everything else is valid, so the
    // row observes the kex-negotiation failure path alone.
    final bogus = SSH_Message_KexInit(
      kexAlgorithms: const ['tp-sshd-audit-bogus-kex'],
      serverHostKeyAlgorithms:   _validClientKexInit().serverHostKeyAlgorithms,
      encryptionClientToServer:
            _validClientKexInit().encryptionClientToServer,
      encryptionServerToClient:
            _validClientKexInit().encryptionServerToClient,
      macClientToServer:   _validClientKexInit().macClientToServer,
      macServerToClient:   _validClientKexInit().macServerToClient,
      compressionClientToServer: const ['none'],
      compressionServerToClient: const ['none'],
      firstKexPacketFollows: false,
    );
    session.transport!.sendPacket(bogus.encode());
    final observations = await session.collect(window: _collectWindow);
    final actual = _describePostAuth(observations.skip(baseline).toList());
    return await _withSshdLogCheck(servers, port, actual, 'Unable to negotiate');
  } finally {
    await session.close();
  }
}

Future<String> _probeB08(AuditServers servers, int port) async {
  final (session, baseline) = await _dialPostAuth(servers, port);
  try {
    // Start the rekey; the KEXINIT goes out on the wire synchronously.
    unawaited(session.transport!.rekey());
    // The violation: an out-of-order NEWKEYS while the exchange is in
    // progress, before the server can have sent its own KEXDH_REPLY /
    // NEWKEYS. A raw sendPacket is used (not the client's kex machinery)
    // so the injected packet is ordinary encrypted traffic at the next
    // sequence number — exactly what a padding attacker would inject.
    session.transport!.sendPacket(SSH_Message_NewKeys().encode());
    final observations = await session.collect(window: _collectWindow);
    final actual = _describePostAuth(observations.skip(baseline).toList());
    return await _withSshdLogCheck(
      servers,
      port,
      actual,
      'Corrupted MAC on input',
    );
  } finally {
    await session.close();
  }
}
