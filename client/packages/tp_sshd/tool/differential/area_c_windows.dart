/// Area C of the tp_sshd differential audit: window handling.
///
/// 10 rows (C01–C10). Every runnable row's OpenSSH expectation was written
/// from the V_10_2_P1 source BEFORE the row ran (see DIFFERENTIAL_AUDIT.md);
/// the runners here only apply the stimulus to both servers and record what
/// came back. Rows C01/C02/C10 are observational: their subject is the
/// window policy itself (the initial grant and the adjustment cadence), not
/// a pass/fail stimulus.
///
/// VM-only tool code: `dart:io` sockets and processes.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/protocol.dart';

import 'area_a_malformed.dart' show AuditRow;
import 'audit_harness.dart';
import 'raw_driver.dart';
import 'row_plumbing.dart';

/// The Area C rows (C01–C10).
List<AuditRow> areaCRows() => [
      row(
        id: 'C01',
        stimulus: 'a session channel opened with a 2048-byte client receive '
            'window, a `cat` exec running, then 1 MiB streamed in 32 KiB chunks: '
            'how much echo comes back before the client grants more, and what '
            'the server WINDOW_ADJUST cadence for the inbound stream looks like',
        citation: 'channels.c:channel_output_poll_input_open (server stops '
            'reading the child at remote_window 0 — echo stalls at the granted '
            'window) + channels.c:channel_check_window (adjust cadence: below '
            'half, or > 3 maxpacket outstanding, and only for really-consumed '
            'bytes) vs server_channel.dart:_flushOutgoing (send side bounded by '
            'the client window) and _grantReceiveWindowIfNeeded (same two '
            'thresholds, but granted on receipt accounting, not consumption)',
        predicted: 'the echo stops at exactly the 2048 granted bytes until the '
            'client adjusts; each +1024 adjust releases exactly 1024 more; the '
            'server never sends past the granted window; inbound-stream adjusts '
            'only when the thresholds cross',
        probe: _probeC01,
      ),
      row(
        id: 'C02',
        stimulus: 'observational: both servers\' initial window grant on a '
            'session channel (CHANNEL_OPEN_CONFIRMATION) and the adjust sequence '
            'around an exec, plus the adjust cadence during a 1 MiB inbound '
            'bulk stream',
        citation:
            'serverloop.c:server_request_session (channel_new with window '
            '0 — a session channel is LARVAL until its first request) + '
            'session.c:session_set_fds -> channels.c:channel_set_fds '
            '(local_window = local_window_max = CHAN_SES_WINDOW_DEFAULT '
            '(2 MiB, channels.h:230) granted via WINDOW_ADJUST once the program '
            'starts) vs server_channel.dart (initialReceiveWindow 2 MiB flat in '
            'the confirmation, no post-exec adjust)',
        predicted:
            'sshd confirms the session channel with window 0 and sends a '
            '2 MiB WINDOW_ADJUST when the exec starts; tp_sshd confirms with '
            '2 MiB flat and sends no post-exec adjust; both end up with the same '
            '2 MiB grant once the program runs',
        probe: _probeC02,
      ),
      row(
        id: 'C03',
        stimulus:
            'a 32768-byte client receive window and an exec that produces '
            '1 MiB (`head -c 1048576 /dev/zero`); the client never reads and '
            'never adjusts',
        citation: 'channels.c:channel_output_poll_input_open (server stops '
            'reading the child once remote_window <= 0 — the child blocks on '
            'its stdout pipe; no timer, no disconnect) vs server_channel.dart:'
            '_flushOutgoing (stalls with the queue intact when _sendWindow <= 0)',
        predicted:
            'both stall silently after sending exactly the granted window '
            '(32768 bytes); no disconnect, connection stays open',
        probe: _probeC03,
      ),
      row(
        id: 'C04',
        stimulus: 'one CHANNEL_DATA of 33000 bytes (> the 32768 maximum packet '
            'size the server granted in the confirmation, but under the shared '
            'transport\'s 35000-byte packet cap so the row observes the CHANNEL '
            'policy and not A03\'s transport length cap) on an open `cat` exec '
            'channel, then a small in-bounds chunk as a liveness probe',
        citation: 'channels.c:channel_input_data (win_len > local_maxpacket -> '
            'logit "rcvd big packet" + return 0: the packet is DROPPED, the '
            'channel and connection live on) vs server_channel.dart:'
            '_handleIncoming (data.length > maximumPacketSize -> _failChannel -> '
            '_finish: the CHANNEL is closed, the connection lives on)',
        predicted: 'sshd drops the oversized packet with no reply and still '
            'echoes the follow-up probe; tp_sshd closes the channel '
            '(CHANNEL_CLOSE) and the follow-up probe gets no echo',
        probe: _probeC04,
      ),
      row(
        id: 'C05',
        stimulus:
            'window exhaustion plus 1 byte: 2 MiB + 32768 + 1 byte into a '
            '`sleep 30` exec (a program that never reads stdin, so nothing is '
            'ever consumed beyond the 64 KiB pipe), then a second phase pushing '
            '~320 KiB more to cross the 10% grace',
        citation: 'channels.c:channel_input_data (win_len > local_window -> '
            'local_window_exceeded accumulates, window zeroed, data still '
            'buffered; past local_window_max/10 -> DISCONNECT(2, "channel N: '
            'peer ignored channel window")) vs server_channel.dart:'
            '_handleIncoming + _grantReceiveWindowIfNeeded (the refill rules '
            'fire on receipt accounting — below half or > 3 packets — with no '
            'consumption and no enforcement, so the window keeps being refilled '
            'instead of exhausted)',
        predicted: 'sshd: the 1-byte overage is tolerated (grace), no reply, '
            'connection open; the second phase crosses the 10% grace and '
            'disconnects with reason 2. tp_sshd: the window is refilled by '
            'accounting throughout — WINDOW_ADJUSTs keep coming and no '
            'disconnect ever fires (A16\'s finding, formalized on a session '
            'channel)',
        probe: _probeC05,
      ),
      row(
        id: 'C06',
        stimulus: 'three WINDOW_ADJUST anomalies in sequence: one addressed to '
            'unknown channel 99999, one adjust of 0 on an open channel, and one '
            'overflowing adjust (+1 on a channel whose send window is already '
            '0xffffffff)',
        citation: 'channels.c:channel_input_window_adjust (unknown channel -> '
            'logit "Received window adjust for non-open channel" + return 0; '
            'adjust 0 is a no-op; new_rwin wrap -> fatal "channel %d: adjust %u '
            'overflows remote window %u") vs server_connection.dart:'
            '_handleChannelMessage (unknown recipient ignored) + '
            'server_channel.dart:handleWindowAdjust (overflow -> _failChannel -> '
            '_finish: channel CLOSE, connection lives on)',
        predicted: 'sshd: the unknown-channel and zero adjusts draw no reply; '
            'the overflowing adjust is fatal — a teardown with no DISCONNECT on '
            'the wire, the reason only in the sshd log. tp_sshd: the first two '
            'are equally silent; the overflow closes the CHANNEL '
            '(CHANNEL_CLOSE) but keeps the connection',
        probe: _probeC06,
      ),
      row(
        id: 'C07',
        stimulus: 'window pressure across a rekey (B01 variant, x3 rounds): a '
            '`cat` exec with a 65536-byte client window, 512 KiB streamed in, '
            'the client adjusting its receive window on a 50 ms pump, and '
            'rekey() called at >= 64 KiB echo; the full echo must come back '
            'byte-intact and the channel must finish',
        citation:
            'packet.c:ssh_packet_send2 (non-KEX outgoing queued during the '
            'exchange, drained in order after NEWKEYS; incoming channel messages '
            'dispatch normally through a rekey) + channels.c:channel_check_window '
            '(adjusts keep flowing across the exchange) vs dartssh2 '
            'ssh_transport.dart (same outgoing queueing; the shared transport\'s '
            'UNIMPLEMENTED drop of non-KEX messages racing INTO the exchange '
            'window is B02\'s recorded finding)',
        predicted: 'sshd: stream completes byte-intact, window adjusts are '
            'honored across the exchange, channel closes cleanly. tp_sshd: the '
            'same, with the B02 caveat — an adjust or data packet racing into '
            'the exchange window may draw UNIMPLEMENTED and be dropped; the '
            '50 ms pump keeps granting, so the stall is transient',
        probe: _probeC07,
      ),
      row(
        id: 'C08',
        stimulus: 'max-channels flood: 11 `session` channel opens on one '
            'connection (tp_sshd caps at maxChannels 10; sshd caps sessions at '
            'MaxSessions, default 10)',
        citation:
            'session.c:session_new (sessions_nalloc >= options.max_sessions '
            '-> NULL) + serverloop.c:server_request_session (session_open fails '
            '-> channel freed, return NULL) + serverloop.c:server_input_channel_'
            'open (NULL -> CHANNEL_OPEN_FAILURE with the initial reason '
            'SSH2_OPEN_CONNECT_FAILED (2) and "open failed") + servconf.h:40 '
            'DEFAULT_SESSIONS_MAX 10 (servconf.c:448-449) vs ssh_server.dart '
            'maxChannels 10 + server_connection.dart:_handleChannelOpen (cap -> '
            'reason 4 resource shortage)',
        predicted: 'both confirm 10 channels and refuse the 11th; the refusal '
            'reason code differs (sshd: 2 "open failed"; tp_sshd: 4 "Too many '
            'open channels (10/10)")',
        probe: _probeC08,
      ),
      row(
        id: 'C09',
        stimulus: 'the 11th channel\'s exact refusal observable, then slot '
            'recovery: after the refusal, close one confirmed channel and open '
            'another',
        citation:
            'serverloop.c:server_input_channel_open (failure reply path) + '
            'channels.c:channel_free (a closed channel\'s slot returns — sshd '
            'frees the session via the cleanup callback) vs server_connection'
            '.dart:onClosed (_channels.remove — the slot returns immediately)',
        predicted: 'both servers: after closing one channel, the next open is '
            'confirmed again (the cap is on live channels, not a lifetime '
            'counter)',
        probe: _probeC09,
      ),
      row(
        id: 'C10',
        stimulus: 'observational: a 4 MiB SFTP round-trip (pipelined WRITEs '
            'then pipelined READs) over a real dartssh2 SftpClient against both '
            'servers — integrity and completion under pipelined request load',
        citation: 'sftp-server.c process() loop (one SFTP request per channel '
            'message, replies in request order; the window the session channel '
            'grants — channels.h CHAN_SES_WINDOW_DEFAULT 2 MiB via session_set_'
            'fds — bounds the pipelining) vs server_sftp.dart (the same request '
            'loop over the channel; dispatch is concurrent against the '
            'filesystem seam)',
        predicted:
            'both servers complete the 4 MiB round-trip with the payload '
            'byte-intact; the pipelined reads ride the 2 MiB session window '
            'without stalls or errors',
        probe: _probeC10,
      ),
    ];

// ---------------------------------------------------------------------------
// Shared probe helpers (Area C local)
// ---------------------------------------------------------------------------

/// How many WINDOW_ADJUST observations arrived, and the bytes they granted.
({int count, int bytes}) _adjustStats(List<Observed> observations) {
  var count = 0;
  var bytes = 0;
  for (final observation in observations) {
    if (observation is MessageObservation &&
        observation.id == SSH_Message_Channel_Window_Adjust.messageId &&
        observation.payload != null) {
      try {
        bytes += SSH_Message_Channel_Window_Adjust.decode(
          observation.payload!,
        ).bytesToAdd;
        count++;
      } on Object {
        // Undecodable adjusts still count as arrivals.
        count++;
      }
    }
  }
  return (count: count, bytes: bytes);
}

// ---------------------------------------------------------------------------
// C01–C10 probes
// ---------------------------------------------------------------------------

Future<String> _probeC01(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    final confirmation = await openSessionChannel(
      session,
      senderChannel: 100,
      clientWindow: 2048,
    );
    final serverChannel = confirmation.senderChannel;
    await requestExec(session, serverChannel, 'cat', since: baseline);
    final afterExec = (await snapshot(session)).length;
    // 1 MiB in 32 KiB chunks: the inbound stream is far larger than any
    // refill threshold, while the echo is pinned to the 2048-byte grant.
    final chunk = Uint8List(32768);
    for (var i = 0; i < 32; i++) {
      session.transport!.sendPacket(
        SSH_Message_Channel_Data(recipientChannel: serverChannel, data: chunk)
            .encode(),
      );
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    var slice = (await snapshot(session)).skip(afterExec).toList();
    final echo = receivedDataBytes(slice);
    final adjusts = _adjustStats(slice);
    // One +1024 client adjust must release exactly 1024 more echo bytes.
    session.transport!.sendPacket(
      SSH_Message_Channel_Window_Adjust(
        recipientChannel: serverChannel,
        bytesToAdd: 1024,
      ).encode(),
    );
    await Future<void>.delayed(const Duration(milliseconds: 700));
    slice = (await snapshot(session)).skip(afterExec).toList();
    final echoAfterAdjust = receivedDataBytes(slice);
    return 'client window 2048, 1 MiB streamed in: echo stalled at $echo '
        'bytes; +1024 client adjust -> $echoAfterAdjust; inbound adjusts: '
        '${adjusts.count} totaling ${adjusts.bytes} bytes '
        '(${describePostAuth(slice)})';
  } finally {
    await session.close();
  }
}

Future<String> _probeC02(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    final confirmation = await openSessionChannel(session, senderChannel: 100);
    final serverChannel = confirmation.senderChannel;
    final afterConfirm = (await snapshot(session)).length;
    await requestExec(session, serverChannel, 'cat', since: afterConfirm);
    // The window grant the confirmation carried, and any adjust that the
    // exec itself produced (sshd's channel_set_fds grant).
    await Future<void>.delayed(const Duration(milliseconds: 400));
    var slice = (await snapshot(session)).skip(afterConfirm).toList();
    final postExecAdjust = _adjustStats(slice);
    final afterExecSettled = (await snapshot(session)).length;
    final chunk = Uint8List(32768);
    for (var i = 0; i < 32; i++) {
      session.transport!.sendPacket(
        SSH_Message_Channel_Data(recipientChannel: serverChannel, data: chunk)
            .encode(),
      );
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    slice = (await snapshot(session)).skip(afterExecSettled).toList();
    final streamAdjusts = _adjustStats(slice);
    return 'confirmation window=${confirmation.initialWindowSize} '
        'maxpacket=${confirmation.maximumPacketSize}; post-exec adjust: '
        '${postExecAdjust.count}x/${postExecAdjust.bytes} bytes; 1 MiB '
        'inbound stream: ${streamAdjusts.count} adjusts totaling '
        '${streamAdjusts.bytes} bytes';
  } finally {
    await session.close();
  }
}

Future<String> _probeC03(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    final confirmation = await openSessionChannel(
      session,
      senderChannel: 100,
      clientWindow: 32768,
    );
    final serverChannel = confirmation.senderChannel;
    await requestExec(
      session,
      serverChannel,
      'head -c 1048576 /dev/zero',
      since: baseline,
    );
    await Future<void>.delayed(const Duration(seconds: 3));
    final first = (await snapshot(session)).skip(baseline).toList();
    final firstBytes = receivedDataBytes(first);
    await Future<void>.delayed(const Duration(seconds: 2));
    final second = (await snapshot(session)).skip(baseline).toList();
    final secondBytes = receivedDataBytes(second);
    final closed = second.any((o) => o is ClosedObservation);
    return 'client window 32768, never adjusted: $firstBytes bytes arrived '
        'in 3s; ${secondBytes - firstBytes} more in the next 2s; '
        '${closed ? 'connection CLOSED' : 'connection still open'}; '
        'non-data replies: ${describePostAuth(second.where((o) => o is! MessageObservation || o.id != SSH_Message_Channel_Data.messageId).toList())}';
  } finally {
    await session.close();
  }
}

Future<String> _probeC04(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    final confirmation = await openSessionChannel(session, senderChannel: 100);
    final serverChannel = confirmation.senderChannel;
    await requestExec(session, serverChannel, 'cat', since: baseline);
    final afterExec = (await snapshot(session)).length;
    // The oversized single chunk: 33000 > the 32768 the server granted,
    // but the whole packet stays under the transport's 35000-byte cap.
    session.transport!.sendPacket(
      SSH_Message_Channel_Data(
        recipientChannel: serverChannel,
        data: Uint8List(33000),
      ).encode(),
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    var slice = (await snapshot(session)).skip(afterExec).toList();
    final response = describePostAuth(slice);
    // Liveness probe: a small in-bounds chunk on the same channel.
    session.transport!.sendPacket(
      SSH_Message_Channel_Data(
        recipientChannel: serverChannel,
        data: Uint8List.fromList('probe\n'.codeUnits),
      ).encode(),
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    slice = (await snapshot(session)).skip(afterExec).toList();
    final echoed = utf8Decode(receivedData(slice)).contains('probe');
    return 'after the 33000-byte chunk: $response; follow-up 6-byte probe '
        '${echoed ? 'echoed (channel alive)' : 'NOT echoed (channel dead)'}';
  } finally {
    await session.close();
  }
}

Future<String> _probeC05(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    final confirmation = await openSessionChannel(session, senderChannel: 100);
    final serverChannel = confirmation.senderChannel;
    await requestExec(session, serverChannel, 'sleep 30', since: baseline);
    final afterExec = (await snapshot(session)).length;
    // Phase 1: drain the 2 MiB window, then one packet and one byte past it.
    final chunk = Uint8List(32768);
    for (var i = 0; i < 65; i++) {
      session.transport!.sendPacket(
        SSH_Message_Channel_Data(recipientChannel: serverChannel, data: chunk)
            .encode(),
      );
    }
    session.transport!.sendPacket(
      SSH_Message_Channel_Data(
        recipientChannel: serverChannel,
        data: Uint8List(1),
      ).encode(),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    var slice = (await snapshot(session)).skip(afterExec).toList();
    final phase1 = describePostAuth(slice);
    final phase1Adjusts = _adjustStats(slice);
    // Phase 2: ~320 KiB more — the child's 64 KiB stdin-pipe slack plus
    // this must cross the 10% grace of a 2 MiB window.
    for (var i = 0; i < 10; i++) {
      session.transport!.sendPacket(
        SSH_Message_Channel_Data(recipientChannel: serverChannel, data: chunk)
            .encode(),
      );
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    slice = (await snapshot(session)).skip(afterExec).toList();
    final phase2 = describePostAuth(slice);
    final phase2Adjusts = _adjustStats(slice);
    return await withSshdLogCheck(
      servers,
      port,
      '2 MiB + 32768 + 1 byte into `sleep 30`: $phase1 '
          '(adjusts ${phase1Adjusts.count}x/${phase1Adjusts.bytes}); '
          '+320 KiB more: $phase2 (adjusts now '
          '${phase2Adjusts.count}x/${phase2Adjusts.bytes})',
      'peer ignored channel window',
    );
  } finally {
    await session.close();
  }
}

Future<String> _probeC06(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    // (1) An adjust for a channel that was never opened.
    session.transport!.sendPacket(
      SSH_Message_Channel_Window_Adjust(
        recipientChannel: 99999,
        bytesToAdd: 1024,
      ).encode(),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final afterUnknown = (await snapshot(session)).length;
    // (2) A channel whose send window is already at the uint32 maximum…
    final confirmation = await openSessionChannel(
      session,
      senderChannel: 100,
      clientWindow: 0xffffffff,
      since: afterUnknown,
    );
    final serverChannel = confirmation.senderChannel;
    final afterConfirm = (await snapshot(session)).length;
    // …an adjust of 0 (a no-op), then…
    session.transport!.sendPacket(
      SSH_Message_Channel_Window_Adjust(
        recipientChannel: serverChannel,
        bytesToAdd: 0,
      ).encode(),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // (3) …an adjust of 1, which overflows past 0xffffffff.
    session.transport!.sendPacket(
      SSH_Message_Channel_Window_Adjust(
        recipientChannel: serverChannel,
        bytesToAdd: 1,
      ).encode(),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    final slice = (await snapshot(session)).skip(afterConfirm).toList();
    final unknownSlice = (await snapshot(
      session,
    ))
        .skip(baseline)
        .take(afterUnknown - baseline)
        .toList();
    return await withSshdLogCheck(
      servers,
      port,
      'unknown-channel adjust: ${describePostAuth(unknownSlice)}; adjust 0 '
          'then +1 on a 0xffffffff window: ${describePostAuth(slice)}',
      'overflows remote window',
    );
  } finally {
    await session.close();
  }
}

/// The C07 echo payload: 512 KiB, each 256-byte block headed by its index.
Uint8List _c07Pattern() {
  const blockSize = 256;
  const total = 512 * 1024;
  final data = Uint8List(total);
  for (var block = 0; block < total ~/ blockSize; block++) {
    final offset = block * blockSize;
    ByteData.sublistView(data, offset, offset + 8)
        .setUint64(0, block, Endian.little);
    for (var i = 8; i < blockSize; i++) {
      data[offset + i] = (block * 31 + i) & 0xff;
    }
  }
  return data;
}

/// How many C07 rounds run per server. Whether a WINDOW_ADJUST or data
/// packet races into the rekey exchange window is a sub-millisecond timing
/// question, so the observable is the distribution over 3 rounds.
const _c07Rounds = 3;

Future<String> _probeC07(AuditServers servers, int port) async {
  final pattern = _c07Pattern();
  final outcomes = <String>[];
  for (var round = 0; round < _c07Rounds; round++) {
    final failure = await _c07Round(servers, port, pattern);
    outcomes.add(failure == null
        ? 'round ${round + 1}: complete, byte-intact, closed cleanly'
        : 'round ${round + 1}: $failure');
  }
  final clean = outcomes.where((o) => o.contains('complete')).length;
  return '$clean/$_c07Rounds rounds clean; ${outcomes.join('; ')}';
}

/// One C07 round: `cat` exec under a 65536-byte client window, 512 KiB
/// streamed in, the client adjusting on a 50 ms pump, rekey() at >= 64 KiB
/// echo. Returns `null` when everything worked, or the failure observable.
Future<String?> _c07Round(
  AuditServers servers,
  int port,
  Uint8List pattern,
) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  Timer? pump;
  try {
    final confirmation = await openSessionChannel(
      session,
      senderChannel: 100,
      clientWindow: 65536,
    );
    final serverChannel = confirmation.senderChannel;
    await requestExec(session, serverChannel, 'cat', since: baseline);
    final afterExec = (await snapshot(session)).length;
    var rekeyed = false;
    var granted = 0;
    // The client-side window pump: grant what has been received every 50 ms,
    // so an adjust dropped into a rekey window (B02's finding) is followed
    // by another instead of a deadlock.
    pump = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final slice = session.currentObservations.skip(afterExec).toList();
      final received = receivedDataBytes(slice);
      final owed = received - granted;
      if (owed > 0) {
        granted += owed;
        try {
          session.transport!.sendPacket(
            SSH_Message_Channel_Window_Adjust(
              recipientChannel: serverChannel,
              bytesToAdd: owed,
            ).encode(),
          );
        } on Object {
          // The transport was torn down by the row itself.
        }
      }
      if (!rekeyed && received >= 65536) {
        rekeyed = true;
        unawaited(session.transport!.rekey());
      }
    });
    // Stream the pattern in 32 KiB chunks, paced so the rekey lands
    // mid-stream rather than before or after it.
    const chunkSize = 32768;
    for (var offset = 0; offset < pattern.length; offset += chunkSize) {
      session.transport!.sendPacket(
        SSH_Message_Channel_Data(
          recipientChannel: serverChannel,
          data: Uint8List.sublistView(pattern, offset, offset + chunkSize),
        ).encode(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
    // The echo must come back complete, then the channel must finish.
    var complete = false;
    try {
      await awaitObservation(
        session,
        (slice) => receivedDataBytes(slice) == pattern.length,
        what: 'the full 512 KiB echo',
        since: afterExec,
        timeout: const Duration(seconds: 8),
      );
      complete = true;
    } on TimeoutException {
      complete = false;
    }
    session.transport!.sendPacket(
      SSH_Message_Channel_EOF(recipientChannel: serverChannel).encode(),
    );
    var channelClosed = false;
    try {
      await awaitMessage(
        session,
        const [SSH_Message_Channel_Close.messageId],
        since: afterExec,
        timeout: const Duration(seconds: 5),
      );
      channelClosed = true;
    } on TimeoutException {
      channelClosed = false;
    }
    final slice = (await snapshot(session)).skip(afterExec).toList();
    final echo = receivedData(slice);
    final unimplemented = slice
        .where(
          (o) =>
              o is MessageObservation &&
              o.id == SSH_Message_Unimplemented.messageId,
        )
        .length;
    if (complete && bytesEqual(echo, pattern) && channelClosed) {
      return null;
    }
    final integrity = bytesEqual(echo, pattern)
        ? 'byte-intact'
        : bytesEqual(echo, pattern.sublist(0, echo.length))
            ? 'truncated (prefix intact)'
            : 'CORRUPTED';
    return 'echo ${echo.length}/${pattern.length} bytes ($integrity), '
        'channel ${channelClosed ? 'closed' : 'NEVER closed'}, '
        'UNIMPLEMENTED seen: $unimplemented';
  } finally {
    pump?.cancel();
    await session.close();
  }
}

Future<String> _probeC08(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    final (confirmed, refusal) = await _openChannels(session, 11);
    return '$confirmed/11 opens confirmed, then $refusal';
  } finally {
    await session.close();
  }
}

/// Opens [count] session channels one by one, stopping at the first
/// refusal. Returns how many were confirmed and the refusal's exact
/// observable (reason code + description).
Future<(int, String)> _openChannels(RawSession session, int count) async {
  var confirmed = 0;
  var refusal = '(no cap hit: all $count confirmed)';
  for (var i = 0; i < count; i++) {
    final since = (await snapshot(session)).length;
    session.transport!.sendPacket(
      SSH_Message_Channel_Open(
        channelType: 'session',
        senderChannel: 200 + i,
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
      final failure = SSH_Message_Channel_Open_Failure.decode(reply!.payload!);
      refusal = 'open #${i + 1} -> CHANNEL_OPEN_FAILURE '
          'reason=${failure.reasonCode} "${failure.description}"';
    }
    break;
  }
  return (confirmed, refusal);
}

Future<String> _probeC09(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    // Open 11: the first 10 confirm, the 11th is the refusal observable.
    var confirmed = 0;
    SSH_Message_Channel_Confirmation? aConfirmation;
    var refusal = '(no refusal observed)';
    for (var i = 0; i < 11; i++) {
      final since = (await snapshot(session)).length;
      session.transport!.sendPacket(
        SSH_Message_Channel_Open(
          channelType: 'session',
          senderChannel: 200 + i,
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
        aConfirmation ??= latestConfirmation(session);
      } else if (reply?.payload != null) {
        final failure =
            SSH_Message_Channel_Open_Failure.decode(reply!.payload!);
        refusal = 'reason=${failure.reasonCode} "${failure.description}"';
        break;
      }
    }
    // Close one confirmed channel, then open another: the freed slot must
    // be reusable.
    final closedChannel = aConfirmation;
    if (closedChannel == null) {
      return 'no channel was ever confirmed; $refusal';
    }
    session.transport!.sendPacket(
      SSH_Message_Channel_Close(
        recipientChannel: closedChannel.senderChannel,
      ).encode(),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final since = (await snapshot(session)).length;
    session.transport!.sendPacket(
      SSH_Message_Channel_Open(
        channelType: 'session',
        senderChannel: 300,
        initialWindowSize: 2 * 1024 * 1024,
        maximumPacketSize: 32768,
      ).encode(),
    );
    String recovery;
    try {
      await awaitMessage(
        session,
        const [
          SSH_Message_Channel_Confirmation.messageId,
          SSH_Message_Channel_Open_Failure.messageId,
        ],
        since: since,
        timeout: const Duration(seconds: 5),
      );
      final reply = latestMessage(
        session,
        const [
          SSH_Message_Channel_Confirmation.messageId,
          SSH_Message_Channel_Open_Failure.messageId,
        ],
        since: since,
      );
      recovery = reply?.id == SSH_Message_Channel_Confirmation.messageId
          ? 'confirmed (slot recovered)'
          : 'REFUSED again';
    } on TimeoutException {
      recovery = 'no reply';
    }
    return '$confirmed/11 opens confirmed; 11th open refused: $refusal; '
        'after closing one channel, a new open: $recovery';
  } finally {
    await session.close();
  }
}

Future<String> _probeC10(AuditServers servers, int port) async {
  const size = 4 * 1024 * 1024;
  final pattern = Uint8List(size);
  for (var i = 0; i < size; i++) {
    pattern[i] = i & 0xff;
  }
  // The two servers jail SFTP differently: tp_sshd's root is the audit
  // sandbox; the system sshd's internal-sftp starts at the real $HOME.
  final path = port == servers.tpdPort ? '/c10-bulk.bin' : 'tp-diff-c10.bin';
  final client = await loginClient(servers, port);
  try {
    final stopwatch = Stopwatch()..start();
    final sftp = await client.sftp();
    try {
      final file = await sftp.open(
        path,
        mode: SftpFileOpenMode.create | SftpFileOpenMode.write,
      );
      await file.writeBytes(pattern);
      await file.close();
      final uploaded = stopwatch.elapsedMilliseconds;
      final reader = await sftp.open(path, mode: SftpFileOpenMode.read);
      final downloaded = await reader.readBytes();
      await reader.close();
      final roundTrip = stopwatch.elapsedMilliseconds;
      final intact = bytesEqual(downloaded, pattern);
      try {
        await sftp.remove(path);
      } on Object {
        // Cleanup is best-effort; the artifact is the transfer, not the file.
      }
      return '4 MiB SFTP round-trip: upload ${uploaded}ms, download '
          '${roundTrip - uploaded}ms, ${downloaded.length} bytes read back, '
          '${intact ? 'byte-intact' : 'CORRUPTED'}';
    } finally {
      await sftp.close();
    }
  } finally {
    await client.close().catchError((_) {});
  }
}

String utf8Decode(Uint8List bytes) => String.fromCharCodes(bytes);
