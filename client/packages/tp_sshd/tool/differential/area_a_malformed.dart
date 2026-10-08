/// Area A of the tp_sshd differential audit: malformed input handling.
///
/// 19 rows (A01–A19), one per stimulus in the audit plan. Every row's
/// OpenSSH expectation was written from the V_10_2_P1 source BEFORE the
/// row ran (see DIFFERENTIAL_AUDIT.md); the runners here only apply the
/// stimulus to both servers and record what came back.
///
/// Observable per row: the messages the server sent after the stimulus
/// (with payload detail for USERAUTH_FAILURE / CHANNEL_OPEN_FAILURE /
/// CHANNEL_OPEN_CONFIRMATION), any DISCONNECT (reason + description),
/// whether the TCP connection closed, and the crash-isolation check (the
/// listener still serves a clean publickey login afterwards).
///
/// VM-only tool code: `dart:io` sockets and processes.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' show SSHClient, SSHKeyPair, SSHSocket;
import 'package:dartssh2/protocol.dart';

import 'audit_harness.dart';
import 'raw_driver.dart';
import 'run_audit.dart';

/// One differential audit row: what it does and how to run it.
class AuditRow {
  const AuditRow({
    required this.id,
    required this.stimulus,
    required this.run,
    required this.sourceHint,
  });

  final String id;
  final String stimulus;
  final Future<RowResult> Function(AuditServers servers) run;

  /// Where in the OpenSSH source the predicted behavior is anchored.
  final String sourceHint;
}

/// The Area A rows (A01–A19). Tasks 3–5 mirror this shape for their areas.
List<AuditRow> areaARows() => [
  _row(
    id: 'A01',
    stimulus: 'garbage line "xxxx" before the version string, then a real '
        'SSH-2.0 handshake',
    citation: 'kex.c:kex_exchange_identification (server pre-banner branch)',
    predicted: 'non-SSH- line from a client is fatal: plaintext '
        '"Invalid SSH identification string." + close',
    probe: _probeA01,
  ),
  _row(
    id: 'A02',
    stimulus: 'version string "SSH-1.99-DartSSH_2.0"',
    citation: 'kex.c:kex_exchange_identification (switch on remote_major); '
        'compat.c:compat_banner',
    predicted: 'accepted (major 1 / minor 99 is no mismatch): banner + '
        'KEXINIT, connection stays open',
    probe: _probeA02,
  ),
  _row(
    id: 'A03',
    stimulus: 'pre-KEX plaintext packet with packet_length 40000 '
        '(> 35000, < 256 KiB), header bytes only',
    citation: 'packet.c:ssh_packet_read_poll2 (need % block_size) + '
        'packet.c:ssh_packet_start_discard; PACKET_MAX_SIZE packet.c:102',
    predicted: 'length passes the 256 KiB cap; the 8-byte alignment check '
        'fails ("padding error") -> DISCONNECT(2, "Packet corrupt") + close',
    probe: _probeA03,
  ),
  _row(
    id: 'A04',
    stimulus: 'pre-KEX plaintext packet with packet_length 0',
    citation: 'packet.c:ssh_packet_read_poll2 (packlen < 1 + 4)',
    predicted: '"Bad packet length 0." -> discard path -> '
        'DISCONNECT(2, "Packet corrupt") + close',
    probe: _probeA04,
  ),
  _row(
    id: 'A05',
    stimulus: 'unknown message id 200 pre-auth (post-KEX, no service request)',
    citation: 'auth2.c:do_authentication2 (ssh_dispatch_init) + '
        'dispatch.c:dispatch_protocol_error',
    predicted: 'SSH_MSG_UNIMPLEMENTED reply, connection stays open',
    probe: _probeA05,
  ),
  _row(
    id: 'A06',
    stimulus: 'unknown message id 201 post-auth',
    citation: 'serverloop.c:server_init_dispatch (ssh_dispatch_init) + '
        'dispatch.c:dispatch_protocol_error',
    predicted: 'SSH_MSG_UNIMPLEMENTED reply, connection stays open',
    probe: _probeA06,
  ),
  _row(
    id: 'A07',
    stimulus: 'SERVICE_REQUEST "audit-bogus-service"',
    citation: 'auth2.c:input_service_request',
    predicted: 'DISCONNECT(2, "bad service request audit-bogus-service")',
    probe: _probeA07,
  ),
  _row(
    id: 'A08',
    stimulus: 'USERAUTH_REQUEST (publickey probe) before any SERVICE_REQUEST',
    citation: 'auth2.c:do_authentication2 + auth2.c:input_service_request '
        '(USERAUTH handler registration)',
    predicted: 'default dispatch_protocol_error answers: '
        'SSH_MSG_UNIMPLEMENTED, connection stays open',
    probe: _probeA08,
  ),
  _row(
    id: 'A09',
    stimulus: 'USERAUTH_REQUEST method "password" '
        '(server config is publickey-only)',
    citation: 'auth2.c:input_userauth_request -> authmethod_lookup; '
        'auth2.c:userauth_finish -> authmethods_get',
    predicted: 'USERAUTH_FAILURE listing the enabled methods ("publickey"), '
        'connection stays open',
    probe: _probeA09,
  ),
  _row(
    id: 'A10',
    stimulus: 'USERAUTH_REQUEST publickey with an undecodable key blob',
    citation: 'auth2-pubkey.c:userauth_pubkey + sshkey.c:sshkey_from_blob',
    predicted: 'key parse fails -> USERAUTH_FAILURE("publickey"), '
        'connection stays open',
    probe: _probeA10,
  ),
  _row(
    id: 'A11',
    stimulus: 'USERAUTH_REQUEST publickey with the real device key but an '
        'invalid signature (challenge bytes corrupted before signing)',
    citation: 'auth2-pubkey.c:userauth_pubkey (have_sig verify path)',
    predicted: 'signature verify fails -> USERAUTH_FAILURE("publickey"), '
        'connection stays open',
    probe: _probeA11,
  ),
  _row(
    id: 'A12',
    stimulus: '7 consecutive publickey probe attempts with a distrusted key',
    citation: 'servconf.h:39 DEFAULT_AUTH_FAIL_MAX (6); auth2.c:userauth_finish '
        '-> auth.c:auth_maxtries_exceeded',
    predicted: 'attempts 1-5 answered USERAUTH_FAILURE("publickey"); the 6th '
        'failure -> DISCONNECT(2, "Too many authentication failures")',
    probe: _probeA12,
  ),
  _row(
    id: 'A13',
    stimulus: 'KEXINIT mid-auth (after a successful publickey login, via the '
        'client transport\'s rekey())',
    citation: 'kex.c:kex_input_newkeys re-registers KEXINIT -> '
        'kex.c:kex_input_kexinit',
    predicted: 'client-initiated rekey: server answers with its own KEXINIT '
        'and the rekey proceeds; connection continues',
    probe: _probeA13,
  ),
  _row(
    id: 'A14',
    stimulus: 'CHANNEL_OPEN "audit-bogus-channel" post-auth',
    citation: 'serverloop.c:server_input_channel_open; '
        'ssh2.h:172 SSH2_OPEN_CONNECT_FAILED',
    predicted: 'CHANNEL_OPEN_FAILURE reason 2, description "open failed"',
    probe: _probeA14,
  ),
  _row(
    id: 'A15',
    stimulus: 'CHANNEL_DATA addressed to recipient channel 99999 (never '
        'opened)',
    citation: 'channels.c:channel_from_packet_id via '
        'channels.c:channel_input_data',
    predicted: 'DISCONNECT(2, "data packet referred to nonexistent channel '
        '99999")',
    probe: _probeA15,
  ),
  _row(
    id: 'A16',
    stimulus: 'CHANNEL_DATA flood on an open direct-tcpip channel (the '
        'session-channel variant never reaches the window check: a '
        'request-less session channel is LARVAL and its data is dropped): '
        '320 x 32000 bytes (~10 MiB, enough to fill the target socket\'s kernel '
        'buffer first, then a 2 MiB window + 10% grace)',
    citation: 'channels.c:channel_input_data; CHAN_TCP_WINDOW_DEFAULT '
        'channels.h:232; serverloop.c:server_request_session (LARVAL); '
        'channels.c:channel_input_data non-open type check',
    predicted: 'excess past 10% of the 2 MiB window -> DISCONNECT(2, '
        '"channel 0: peer ignored channel window")',
    probe: _probeA16,
  ),
  _row(
    id: 'A17',
    stimulus: 'GLOBAL_REQUEST "audit-bogus@tp-sshd-differential" with '
        'want_reply = true',
    citation: 'serverloop.c:server_input_global_request',
    predicted: 'REQUEST_FAILURE reply, connection stays open',
    probe: _probeA17,
  ),
  _row(
    id: 'A18',
    stimulus: 'client DISCONNECT(11) sent right after the version exchange '
        '(mid-handshake, pre-KEX)',
    citation: 'packet.c:ssh_packet_read_poll_seqnr (DISCONNECT is '
        'intercepted in every phase)',
    predicted: 'logged, no reply, clean teardown; the listener serves the '
        'next login',
    probe: _probeA18,
  ),
  _row(
    id: 'A19',
    stimulus: 'a non-KEX packet (SERVICE_REQUEST) injected after the client '
        'KEXINIT and before any NEWKEYS, with strict kex negotiated (the '
        'KEXINIT advertises kex-strict-c-v00@openssh.com) — the strict-kex '
        'violation of RFC 9142 §3.2',
    citation: 'packet.c:ssh_packet_read_poll_seqnr (during initial strict KEX '
        'nothing is implicitly handled) + kex.c:kex_protocol_error (strict '
        'branch: KEX_INITIAL && kex_strict) -> packet.c:ssh_packet_disconnect '
        '-> packet.c:sshpkt_disconnect (SSH2_DISCONNECT_PROTOCOL_ERROR, '
        'ssh2.h:153); marker detection kex.c:kex_choose_conf',
    predicted: 'DISCONNECT(2, "strict KEX violation: unexpected packet type 5 '
        '(seqnr 1)") flushed to the wire (ssh_packet_disconnect waits for the '
        'write), then close',
    probe: _probeA19,
  ),
];

// ---------------------------------------------------------------------------
// Row plumbing
// ---------------------------------------------------------------------------

typedef _Probe = Future<String> Function(AuditServers servers, int port);

const _collectWindow = Duration(seconds: 2);
const _kexTimeout = Duration(seconds: 10);

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
  // a clean publickey login (for tp_sshd this is the in-process survival
  // check; for sshd it is the control).
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

/// Runs one probe, converting a crash or timeout into a recorded actual
/// instead of taking the whole audit run down with it.
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

/// A clean publickey login against one audit server (no session traffic).
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
      await client.authenticated.timeout(const Duration(seconds: 10));
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

// ---------------------------------------------------------------------------
// Observation rendering
// ---------------------------------------------------------------------------

/// Renders observations compactly, run-length collapsing repeats
/// (e.g. "msg:51(USERAUTH_FAILURE, methods=[publickey]) x5").
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

/// Renders what a raw-mode dial observed: the server banner, the ASCII
/// error lines and/or plaintext packets that followed it, and whether the
/// connection closed. Pre-KEX everything is plaintext, so both the server's
/// DISCONNECT packets and its pre-protocol error lines are decodable.
String _describeRaw(List<Uint8List> rawInbound, List<Observed> observations) {
  final builder = BytesBuilder(copy: false);
  for (final chunk in rawInbound) {
    builder.add(chunk);
  }
  var rest = builder.takeBytes();
  final parts = <String>[];
  final bannerEnd = _indexOfCrlf(rest);
  if (bannerEnd < 0) {
    parts.add('banner(incomplete)="${_latin1Decode(rest)}"');
    rest = Uint8List(0);
  } else {
    parts.add('banner="${_latin1Decode(rest.sublist(0, bannerEnd))}"');
    rest = rest.sublist(bannerEnd + 2);
  }
  while (rest.isNotEmpty) {
    // A plaintext packet: plausible length + padding, consumed whole.
    final packet = _tryParsePlainTextPacket(rest);
    if (packet != null) {
      if (packet.payload[0] == SSH_Message_Disconnect.messageId) {
        final disconnect = _decodeDisconnectPayload(packet.payload);
        if (disconnect != null) {
          parts.add(
            'disconnect:${disconnect.reason}("${disconnect.description}")',
          );
          rest = rest.sublist(packet.totalLength);
          continue;
        }
      }
      parts.add('packet(id=${packet.payload[0]})');
      rest = rest.sublist(packet.totalLength);
      continue;
    }
    // An ASCII pre-protocol line (e.g. OpenSSH's banner-exchange errors).
    final lineEnd = _indexOfCrlf(rest);
    if (lineEnd >= 0) {
      parts.add('line="${_latin1Decode(rest.sublist(0, lineEnd))}"');
      rest = rest.sublist(lineEnd + 2);
      continue;
    }
    parts.add('${rest.length} trailing bytes');
    break;
  }
  final closed = observations.any((o) => o is ClosedObservation);
  parts.add(closed ? 'closed' : 'open');
  return parts.join('; ');
}

String _latin1Decode(Uint8List bytes) => String.fromCharCodes(bytes);

int _indexOfCrlf(Uint8List bytes) {
  for (var i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] == 0x0d && bytes[i + 1] == 0x0a) return i;
  }
  return -1;
}

({Uint8List payload, int totalLength})? _tryParsePlainTextPacket(
  Uint8List bytes,
) {
  if (bytes.length < 5) return null;
  final length = ByteData.sublistView(bytes, 0, 4).getUint32(0);
  if (length < 5 || length > 65536 || 4 + length > bytes.length) return null;
  final paddingLength = bytes[4];
  if (paddingLength < 4 || 1 + paddingLength >= length) return null;
  return (
    payload: bytes.sublist(5, 4 + length - paddingLength),
    totalLength: 4 + length,
  );
}

({int reason, String description})? _decodeDisconnectPayload(
  Uint8List payload,
) {
  if (payload.length < 9) return null;
  final reason = ByteData.sublistView(payload, 1, 5).getUint32(0);
  final descriptionLength = ByteData.sublistView(payload, 5, 9).getUint32(0);
  if (9 + descriptionLength > payload.length) return null;
  return (
    reason: reason,
    description: _latin1Decode(payload.sublist(9, 9 + descriptionLength)),
  );
}

Future<List<Observed>> _snapshot(RawSession session) =>
    session.collect(window: Duration.zero);

// ---------------------------------------------------------------------------
// Shared probe scaffolding
// ---------------------------------------------------------------------------

/// Dials with [dial], waits for [ready], snapshots a baseline, applies
/// [stimulus], and describes only what arrived after it.
Future<String> _transportProbe(
  Future<RawSession> Function(int port) dial,
  AuditServers servers,
  int port, {
  required Future<void> Function(RawSession session) ready,
  required Future<void> Function(RawSession session) stimulus,
  Duration window = _collectWindow,
}) async {
  final session = await dial(port);
  try {
    await ready(session);
    final baseline = await _snapshot(session);
    await stimulus(session);
    final observations = await session.collect(window: window);
    return _describe(observations.skip(baseline.length).toList());
  } finally {
    await session.close();
  }
}

/// Polls until a message with one of [ids] was observed (or times out).
Future<void> _awaitMessage(
  RawSession session,
  List<int> ids, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final observations = await _snapshot(session);
    if (observations.any(
      (o) => o is MessageObservation && ids.contains(o.id),
    )) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('message ${ids.join('/')} not observed');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Polls until the server banner line has arrived (raw mode only), so a
/// hand-crafted packet is not racing the version exchange.
Future<void> _awaitBanner(RawSession session) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (session.rawInbound.isEmpty) {
    if (DateTime.now().isAfter(deadline)) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await Future<void>.delayed(const Duration(milliseconds: 50));
}

/// A pre-KEX plaintext SSH binary packet (RFC 4253 §6): length +
/// padding-length + payload + at least 4 bytes of padding, aligned to 8.
Uint8List _plainPacket(Uint8List payload) {
  var padding = 4;
  while ((4 + 1 + payload.length + padding) % 8 != 0) {
    padding++;
  }
  final packet = Uint8List(4 + 1 + payload.length + padding);
  ByteData.sublistView(packet, 0, 4)
      .setUint32(0, 1 + payload.length + padding);
  packet[4] = padding;
  packet.setRange(5, 5 + payload.length, payload);
  return packet;
}

/// The 4-byte big-endian packet length header, plus [extra] filler bytes
/// (the pre-KEX length checks fire on the header alone).
Uint8List _lengthHeader(int length, [int extra = 4]) {
  final bytes = Uint8List(4 + extra);
  ByteData.sublistView(bytes, 0, 4).setUint32(0, length);
  return bytes;
}

SSHKeyPair _deviceKey(AuditServers servers) =>
    SSHKeyPair.fromPem(servers.deviceKeyPem).single;

/// Sends the ssh-userauth SERVICE_REQUEST and waits for the SERVICE_ACCEPT,
/// the shared prefix of the auth-phase rows.
Future<void> _negotiateUserService(RawSession session) async {
  session.transport!.sendPacket(
    SSH_Message_Service_Request('ssh-userauth').encode(),
  );
  await _awaitMessage(session, const [SSH_Message_Service_Accept.messageId]);
}

// ---------------------------------------------------------------------------
// Throwaway distrusted identity (never authorized by either server)
// ---------------------------------------------------------------------------

const _distrustedKeyPem = '''
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACDSdzlLnpxXE7tN7CXYZ1TfVj/+25ZtH+y/JgxrqYySKQAAAKhm0DMWZtAz
FgAAAAtzc2gtZWQyNTUxOQAAACDSdzlLnpxXE7tN7CXYZ1TfVj/+25ZtH+y/JgxrqYySKQ
AAAEAZof9yto5xPkzTG+9/x2G4uWctdUB+Un3XFOkELwxXgtJ3OUuenFcTu03sJdhnVN9W
P/7blm0f7L8mDGupjJIpAAAAH3RwLXNzaGQtYXVkaXQtZGlzdHJ1c3RlZC1kZXZpY2UBAg
MEBQY=
-----END OPENSSH PRIVATE KEY-----
''';

final _distrustedKey = SSHKeyPair.fromPem(_distrustedKeyPem).single;

// ---------------------------------------------------------------------------
// Rows A01–A04, A18, A19: raw byte stream, pre-KEX
// ---------------------------------------------------------------------------

Future<String> _probeA01(AuditServers servers, int port) async {
  final session = await dialRaw(port: port, versionString: 'xxxx');
  try {
    await session.sendRawBytes(_line('SSH-2.0-DartSSH_2.0'));
    final observations = await session.collect(window: _collectWindow);
    return _describeRaw(session.rawInbound, observations);
  } finally {
    await session.close();
  }
}

Uint8List _line(String text) =>
    Uint8List.fromList('$text\r\n'.codeUnits);

Future<String> _probeA02(AuditServers servers, int port) async {
  final session = await dialRaw(port: port, versionString: 'SSH-1.99-DartSSH_2.0');
  try {
    final observations = await session.collect(window: _collectWindow);
    return _describeRaw(session.rawInbound, observations);
  } finally {
    await session.close();
  }
}

Future<String> _probeA03(AuditServers servers, int port) async {
  final session = await dialRaw(port: port, versionString: 'SSH-2.0-DartSSH_2.0');
  try {
    await _awaitBanner(session);
    await session.sendRawBytes(_lengthHeader(40000));
    final observations = await session.collect(window: _collectWindow);
    return await _withSshdLogCheck(
      servers,
      port,
      _describeRaw(session.rawInbound, observations),
      'need 39996',
    );
  } finally {
    await session.close();
  }
}

Future<String> _probeA04(AuditServers servers, int port) async {
  final session = await dialRaw(port: port, versionString: 'SSH-2.0-DartSSH_2.0');
  try {
    await _awaitBanner(session);
    await session.sendRawBytes(_lengthHeader(0));
    final observations = await session.collect(window: _collectWindow);
    return await _withSshdLogCheck(
      servers,
      port,
      _describeRaw(session.rawInbound, observations),
      'Bad packet length 0.',
    );
  } finally {
    await session.close();
  }
}

Future<String> _probeA18(AuditServers servers, int port) async {
  final session = await dialRaw(port: port, versionString: 'SSH-2.0-DartSSH_2.0');
  try {
    await _awaitBanner(session);
    final writer = SSHMessageWriter();
    writer.writeUint8(SSH_Message_Disconnect.messageId);
    writer.writeUint32(11); // disconnected by application
    writer.writeUtf8('tp-sshd differential audit A18');
    writer.writeUtf8('');
    await session.sendRawBytes(_plainPacket(writer.takeBytes()));
    final observations = await session.collect(window: _collectWindow);
    return _describeRaw(session.rawInbound, observations);
  } finally {
    await session.close();
  }
}

/// A well-formed client KEXINIT that negotiates strict kex: the
/// `kex-strict-c-v00@openssh.com` marker in the kex name-list is what makes
/// the server enable the strict rules (kex.c:kex_choose_conf /
/// dartssh2 `_negotiateStrictKex`). The real algorithms mirror the standard
/// proposals both servers accept, so the exchange actually starts — the row
/// must reach the server mid-KEX, not die in algorithm negotiation.
SSH_Message_KexInit _strictKexClientKexInit() => SSH_Message_KexInit(
      kexAlgorithms: const [
        'curve25519-sha256',
        'kex-strict-c-v00@openssh.com',
      ],
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

Future<String> _probeA19(AuditServers servers, int port) async {
  final session = await dialRaw(port: port, versionString: 'SSH-2.0-DartSSH_2.0');
  try {
    await _awaitBanner(session);
    // The exchange must be in progress but pre-NEWKEYS: everything here is
    // plaintext, so the whole start of the handshake is hand-driven.
    await session.sendRawBytes(
      _plainPacket(_strictKexClientKexInit().encode()),
    );
    // The violation: a non-KEX packet between KEXINIT and NEWKEYS. The
    // injected type is SERVICE_REQUEST (5), not the plan memo's other
    // examples (USERAUTH_REQUEST 50 / CHANNEL_OPEN 90): types above the KEX
    // dispatch range (SSH2_MSG_TRANSPORT_MAX 49) are fatal on sshd whether
    // or not strict kex is on (the dispatch table entry is NULL during
    // KEX), while a transport-range type is exactly what
    // kex.c:kex_protocol_error's strict branch polices — with strict kex
    // off it would merely draw UNIMPLEMENTED, so the row observes the
    // strict-mode behavior and not the dispatch-table behavior.
    await session.sendRawBytes(
      _plainPacket(SSH_Message_Service_Request('ssh-userauth').encode()),
    );
    final observations = await session.collect(window: _collectWindow);
    return await _withSshdLogCheck(
      servers,
      port,
      _describeRaw(session.rawInbound, observations),
      'strict KEX violation',
    );
  } finally {
    await session.close();
  }
}

// ---------------------------------------------------------------------------
// Rows A05–A13: post-KEX transport, auth phase
// ---------------------------------------------------------------------------

Future<String> _probeA05(AuditServers servers, int port) async {
  // UNIMPLEMENTED is recorded from the transport trace, not from a decoded
  // packet, so this row's OpenSSH actual is cross-checked against sshd's own
  // DEBUG3 log (harness caveat b: trace recording must not under-record).
  return _withSshdLogCheck(
    servers,
    port,
    await _transportProbe(
      (port) => dialPostKex(port: port),
      servers,
      port,
      ready: (session) => session.keyExchangeDone.timeout(_kexTimeout),
      stimulus: (session) async {
        session.transport!.sendPacket(Uint8List.fromList([200]));
      },
    ),
    'type 200',
  );
}

Future<String> _sshdLogHas(AuditServers servers, String needle) async {
  await Future<void>.delayed(const Duration(milliseconds: 300));
  try {
    final log = File(servers.sshdLogPath);
    if (!log.existsSync()) return '(no log)';
    final hit = log.readAsLinesSync().any((line) => line.contains(needle));
    return hit ? 'confirms "$needle"' : 'does NOT contain "$needle"';
  } on Object catch (error) {
    return '(log read failed: $error)';
  }
}

/// The OpenSSH-side actual with the sshd DEBUG3 log cross-check appended.
/// Rows whose wire observable is a bare close (the DISCONNECT is queued but
/// never flushed) or that race an RST rely on the log to confirm the source
/// path actually taken.
Future<String> _withSshdLogCheck(
  AuditServers servers,
  int port,
  String result,
  String needle,
) async {
  if (port != servers.sshdPort) return result;
  return '$result; sshd log: ${await _sshdLogHas(servers, needle)}';
}

Future<String> _probeA06(AuditServers servers, int port) {
  return _authenticatedProbe(
    servers,
    port,
    stimulus: (session) async {
      session.transport!.sendPacket(Uint8List.fromList([201]));
    },
  );
}

/// Shared post-auth scaffolding: dial, authenticate, baseline, stimulus.
Future<String> _authenticatedProbe(
  AuditServers servers,
  int port, {
  required Future<void> Function(RawSession session) stimulus,
  Duration window = _collectWindow,
  Future<void> Function(RawSession session)? verify,
}) {
  return _transportProbe(
    (port) => dialAuthenticated(
      port: port,
      identity: _deviceKey(servers),
      username: servers.username,
    ),
    servers,
    port,
    ready: (session) async {
      await session.authenticated.timeout(_kexTimeout);
      await verify?.call(session);
    },
    stimulus: stimulus,
    window: window,
  );
}

Future<String> _probeA07(AuditServers servers, int port) {
  return _transportProbe(
    (port) => dialPostKex(port: port),
    servers,
    port,
    ready: (session) => session.keyExchangeDone.timeout(_kexTimeout),
    stimulus: (session) async {
      session.transport!.sendPacket(
        SSH_Message_Service_Request('audit-bogus-service').encode(),
      );
    },
  );
}

Future<String> _probeA08(AuditServers servers, int port) {
  return _transportProbe(
    (port) => dialPostKex(port: port),
    servers,
    port,
    ready: (session) => session.keyExchangeDone.timeout(_kexTimeout),
    stimulus: (session) async {
      session.transport!.sendPacket(_publicKeyProbe(servers).encode());
    },
  );
}

/// A well-formed publickey probe request (no signature) for the device key.
SSH_Message_Userauth_Request _publicKeyProbe(AuditServers servers) {
  return SSH_Message_Userauth_Request.publicKey(
    username: servers.username,
    publicKeyAlgorithm: 'ssh-ed25519',
    publicKey: _deviceKey(servers).toPublicKey().encode(),
    signature: null,
  );
}

Future<String> _probeA09(AuditServers servers, int port) {
  return _transportProbe(
    (port) => dialPostKex(port: port),
    servers,
    port,
    ready: (session) async {
      await session.keyExchangeDone.timeout(_kexTimeout);
      await _negotiateUserService(session);
    },
    stimulus: (session) async {
      session.transport!.sendPacket(
        SSH_Message_Userauth_Request.password(
          user: servers.username,
          password: 'audit-wrong-password',
        ).encode(),
      );
    },
  );
}

Future<String> _probeA10(AuditServers servers, int port) {
  return _transportProbe(
    (port) => dialPostKex(port: port),
    servers,
    port,
    ready: (session) async {
      await session.keyExchangeDone.timeout(_kexTimeout);
      await _negotiateUserService(session);
    },
    stimulus: (session) async {
      session.transport!.sendPacket(
        SSH_Message_Userauth_Request.publicKey(
          username: servers.username,
          publicKeyAlgorithm: 'ssh-ed25519',
          // Truncated garbage: the "key" claims 3 name bytes then ends, so
          // no decoder can read a key out of it.
          publicKey: Uint8List.fromList([0, 0, 0, 3, 1, 2, 3]),
          signature: null,
        ).encode(),
      );
    },
  );
}

Future<String> _probeA11(AuditServers servers, int port) async {
  final identity = _deviceKey(servers);
  final session = await dialAuthenticated(
    port: port,
    identity: identity,
    username: servers.username,
    signChallenge: (challenge) {
      final corrupted = Uint8List.fromList(challenge);
      corrupted[corrupted.length - 1] ^= 0xff;
      return identity.sign(corrupted).encode();
    },
  );
  try {
    // The stimulus is the dialer's own signed request; describe the whole
    // auth phase (service negotiation + userauth replies).
    await _awaitMessage(session, const [
      SSH_Message_Userauth_Failure.messageId,
      SSH_Message_Userauth_Success.messageId,
      SSH_Message_Disconnect.messageId,
    ]);
    final observations = await session.collect(window: _collectWindow);
    return _describeAuthPhase(observations);
  } finally {
    await session.close();
  }
}

/// The auth-phase slice of a connection's observations: service
/// negotiation, userauth replies, disconnects and closes.
String _describeAuthPhase(List<Observed> observations) {
  const authIds = {
    SSH_Message_Service_Accept.messageId,
    SSH_Message_Userauth_Failure.messageId,
    SSH_Message_Userauth_Success.messageId,
  };
  return _describe(
    observations
        .where(
          (o) =>
              o is! MessageObservation ||
              authIds.contains(o.id) ||
              o.id == SSH_Message_Disconnect.messageId,
        )
        .toList(),
  );
}

Future<String> _probeA12(AuditServers servers, int port) async {
  final session = await dialPostKex(port: port);
  try {
    await session.keyExchangeDone.timeout(_kexTimeout);
    await _negotiateUserService(session);
    final baseline = await _snapshot(session);
    final probe = SSH_Message_Userauth_Request.publicKey(
      username: servers.username,
      publicKeyAlgorithm: 'ssh-ed25519',
      publicKey: _distrustedKey.toPublicKey().encode(),
      signature: null,
    );
    for (var attempt = 0; attempt < 7; attempt++) {
      try {
        session.transport!.sendPacket(probe.encode());
      } on Object {
        // The transport died on an earlier attempt (the expected outcome);
        // the remaining sends have nothing left to prove.
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final observations = await session.collect(
      window: const Duration(seconds: 3),
    );
    return _describeAuthPhase(observations.skip(baseline.length).toList());
  } finally {
    await session.close();
  }
}

Future<String> _probeA13(AuditServers servers, int port) {
  return _authenticatedProbe(
    servers,
    port,
    stimulus: (session) async {
      // The transport's own rekey(): a well-formed KEXINIT mid-auth whose
      // exchange the driver can also complete (a hand-crafted KEXINIT would
      // desynchronize the client-side kex state machine and end the row on
      // a driver artifact, not on server behavior).
      await session.transport!.rekey();
    },
    window: const Duration(seconds: 3),
  );
}

// ---------------------------------------------------------------------------
// Rows A14–A17: post-auth channel / global-request phase
// ---------------------------------------------------------------------------

Future<String> _probeA14(AuditServers servers, int port) {
  return _authenticatedProbe(
    servers,
    port,
    stimulus: (session) async {
      session.transport!.sendPacket(
        SSH_Message_Channel_Open(
          channelType: 'audit-bogus-channel',
          senderChannel: 0,
          initialWindowSize: 2097152,
          maximumPacketSize: 32768,
        ).encode(),
      );
    },
  );
}

Future<String> _probeA15(AuditServers servers, int port) {
  return _authenticatedProbe(
    servers,
    port,
    stimulus: (session) async {
      session.transport!.sendPacket(
        SSH_Message_Channel_Data(
          recipientChannel: 99999,
          data: Uint8List.fromList([0x78]),
        ).encode(),
      );
    },
  );
}

Future<String> _probeA16(AuditServers servers, int port) async {
  // A silent loopback target: the flood needs a channel that is OPEN on
  // both servers. A bare session channel does not qualify on OpenSSH — a
  // session channel stays SSH_CHANNEL_LARVAL until its first
  // CHANNEL_REQUEST and channel_input_data drops data for non-open
  // channels before any window accounting. A direct-tcpip channel is
  // OPEN once the dial completes (the confirmation we await).
  final target = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  try {
    return await _withSshdLogCheck(
      servers,
      port,
      await _authenticatedProbe(
        servers,
        port,
        verify: (session) async {
          session.transport!.sendPacket(
            SSH_Message_Channel_Open.directTcpip(
              senderChannel: 100,
              initialWindowSize: 2097152,
              maximumPacketSize: 32768,
              host: '127.0.0.1',
              port: target.port,
              originatorIP: '127.0.0.1',
              originatorPort: 12345,
            ).encode(),
          );
          await _awaitMessage(
            session,
            const [SSH_Message_Channel_Confirmation.messageId],
          );
        },
        stimulus: (session) async {
          final chunk = Uint8List(32000);
          for (var i = 0; i < chunk.length; i++) {
            chunk[i] = i & 0xff;
          }
          for (var packet = 0; packet < 320; packet++) {
            try {
              session.transport!.sendPacket(
                SSH_Message_Channel_Data(recipientChannel: 0, data: chunk).encode(),
              );
            } on Object {
              break; // transport already torn down by the row itself
            }
          }
        },
        window: const Duration(seconds: 4),
      ),
      'peer ignored channel window',
    );
  } finally {
    await target.close();
  }
}

Future<String> _probeA17(AuditServers servers, int port) {
  return _authenticatedProbe(
    servers,
    port,
    stimulus: (session) async {
      session.transport!.sendPacket(
        SSH_Message_Global_Request(
          requestName: 'audit-bogus@tp-sshd-differential',
          wantReply: true,
        ).encode(),
      );
    },
  );
}
