/// Area D of the tp_sshd differential audit: channel close races.
///
/// 10 rows (D01–D10). Every runnable row's OpenSSH expectation was written
/// from the V_10_2_P1 source BEFORE the row ran (see DIFFERENTIAL_AUDIT.md);
/// the runners here only apply the stimulus to both servers and record what
/// came back. In 10.2 the channel teardown state machine lives in nchan.c
/// (chan_rcvd_ieof / chan_rcvd_oclose / chan_is_dead) and the session exit
/// path in session.c (session_close_by_pid -> session_exit_message), which
/// is where these citations point.
///
/// VM-only tool code: `dart:io` sockets and processes.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/protocol.dart';

import 'area_a_malformed.dart' show AuditRow;
import 'audit_harness.dart';
import 'raw_driver.dart';
import 'row_plumbing.dart';

/// The Area D rows (D01–D10).
List<AuditRow> areaDRows() => [
      row(
        id: 'D01',
        stimulus:
            'client EOF followed by more CHANNEL_DATA: a `cat > /dev/null; '
            'sleep 30` exec channel keeps running after the client sends '
            'CHANNEL_EOF (the cat half ends, the sleep half holds the channel '
            'open), then the client sends more data on the same channel',
        citation: 'channels.c:channel_input_data (no EOF check on plain data; '
            'the ostate != CHAN_OUTPUT_OPEN branch after EOF fake-consumes the '
            'data — window accounting only, bytes dropped, no reply; only '
            'EXTENDED data after EOF disconnects, channels.c:channel_input_'
            'extended_data) vs server_channel.dart:handleEof (closes the input '
            'stream controller) + _handleIncoming (controller.add on the closed '
            'controller throws, propagating out of the transport dispatch into '
            'closeWithError — a bare teardown)',
        predicted: 'sshd: the post-EOF data is silently dropped (window '
            'accounting only), no reply, connection stays open. tp_sshd: the '
            'post-EOF data throws inside the channel — the whole connection is '
            'torn down with nothing on the wire',
        probe: _probeD01,
      ),
      row(
        id: 'D02',
        stimulus: 'CHANNEL_CLOSE while server output is pending window credit: '
            'an exec producing 256 KiB against a 4096-byte client window (phase '
            '1: client CLOSE after the first 4096 bytes), plus the server-side '
            'exit path under the same pressure (phase 2: no client close — '
            'when do EOF/CLOSE land relative to exit-status?)',
        citation: 'nchan.c:chan_rcvd_oclose (ostate -> WAIT_DRAIN: a received '
            'CLOSE waits for the output to drain — with no window credit it '
            'waits forever; the exit path instead drops it: session.c:'
            'session_exit_message -> chan_write_failed -> nchan.c:'
            'chan_shutdown_write resets the output buffer) vs server_channel'
            '.dart:handleClose (-> _finish: the pending queue is dropped and '
            'CHANNEL_CLOSE sent immediately) and close (the 2 s closeFlushTimeout '
            'bound before EOF + CLOSE)',
        predicted: 'phase 1: sshd goes silent (the channel waits to drain '
            'forever, no CLOSE back), tp_sshd answers CHANNEL_CLOSE immediately '
            '(bounded, deterministic teardown). phase 2: sshd sends '
            'exit-status then EOF then CLOSE at once (the pending tail is '
            'dropped); tp_sshd sends exit-status, then EOF + CLOSE after its 2 s '
            'bounded flush wait',
        probe: _probeD02,
      ),
      row(
        id: 'D03',
        stimulus: 'both sides EOF: an `echo done` exec, the client sending '
            'CHANNEL_EOF right after the exec reply — who sends CHANNEL_CLOSE '
            'first, and in what order does the teardown land?',
        citation:
            'nchan.c:chan_rcvd_ieof (client EOF parks the server output in '
            'WAIT_DRAIN) + nchan.c:chan_is_dead/chan_send_close2 (once both '
            'input and output are closed the server sends CLOSE itself) + '
            'session.c:session_close_by_pid -> session_exit_message (the child '
            'exit drives exit-status -> EOF -> CLOSE) vs server_channel.dart '
            '(_pipeProcess: exitCode -> sendExitStatus -> close() -> EOF -> '
            'CLOSE)',
        predicted: 'both servers: the server sends CHANNEL_CLOSE (the client '
            'only EOFs), and the order is data -> exit-status -> EOF -> CLOSE',
        probe: _probeD03,
      ),
      row(
        id: 'D04',
        stimulus: 'exit-status ordering without any client EOF: an `echo ok` '
            'exec where the client never half-closes — the observable is the '
            'order of exit-status / EOF / CLOSE and the exit status value',
        citation: 'session.c:session_close_by_pid -> session.c:session_exit_'
            'message (channel_request_start "exit-status" FIRST, then '
            'chan_write_failed) + nchan.c:chan_ibuf_empty -> chan_send_eof2 '
            '(EOF once the child\'s stdin pipe drains) + nchan.c:chan_is_dead -> '
            'chan_send_close2 (CLOSE last) vs server_channel.dart:sendExitStatus '
            '+ _pipeProcess (exitCode awaited, then sendExitStatus, then close() '
            '-> EOF -> CLOSE)',
        predicted: 'both servers: CHANNEL_SUCCESS, then data "ok\\n", then '
            'exit-status(0), then EOF, then CLOSE — exit-status strictly before '
            'EOF and CLOSE',
        probe: _probeD04,
      ),
      row(
        id: 'D05',
        stimulus:
            'a CHANNEL_REQUEST racing past the channel\'s death: after the '
            'server has fully closed an exec channel (its CHANNEL_CLOSE observed '
            'and acknowledged), the client sends one more `env` request with '
            'want_reply on that channel',
        citation: 'serverloop.c:server_input_channel_req (channel_lookup fails '
            'once the channel is freed -> ssh_packet_disconnect "server_input_'
            'channel_req: unknown channel %d") vs server_connection.dart:'
            '_handleChannelMessage (_channelOrNull returns null for the removed '
            'channel -> the request is silently ignored)',
        predicted: 'sshd: DISCONNECT(2, "server_input_channel_req: unknown '
            'channel <id>"), connection torn down. tp_sshd: no reply at all, '
            'connection stays open (the A15 family)',
        probe: _probeD05,
      ),
      row(
        id: 'D06',
        stimulus: 'an abrupt TCP reset mid-channel (observational): an exec '
            'streaming 1 MiB, the client destroying the socket with SO_LINGER 0 '
            'while data is in flight — both sides\' teardown and survival',
        citation: 'sshd-session.c:sshd_session_srv / serverloop.c (the read '
            'error path: connection teardown, SIGCHLD reaping of the exec '
            'child, the listener itself untouched) vs server_connection.dart:'
            '_onTransportClosed (channels detached, forwarder released; the '
            'in-process server must survive) + server_channel.dart:detach',
        predicted: 'both servers tear the connection down and keep serving: '
            'sshd logs the connection reset and reaps the child; tp_sshd '
            'detaches the channel without leaking an unhandled async error '
            '(the runner\'s zone is the leak detector)',
        probe: _probeD06,
      ),
      row(
        id: 'D07',
        stimulus:
            'CHANNEL_CLOSE from the client before any EOF, while the exec '
            '(`sleep 2`) is still running',
        citation: 'nchan.c:chan_rcvd_oclose (input shutdown, output to '
            'WAIT_DRAIN) + channels.c:channel_garbage_collect (the session\'s '
            'detach callback is registered with force=0 — serverloop.c:'
            'server_request_session — so the channel is held "almost dead" '
            'until the child exits; then session.c:session_close_by_pid still '
            'delivers exit-status and CLOSE, no EOF) vs server_channel.dart:'
            'handleClose (-> _finish immediately: CLOSE sent, the process '
            'killed, no exit-status)',
        predicted: 'sshd: no reply to the CLOSE while the child lives; ~2 s '
            'later (child exit) exit-status then CLOSE, no EOF. tp_sshd: '
            'CHANNEL_CLOSE echoed immediately, the process killed, no '
            'exit-status ever',
        probe: _probeD07,
      ),
      row(
        id: 'D08',
        stimulus: 'a server-initiated `forwarded-tcpip` channel (tcpip-forward '
            'to 127.0.0.1:0, one connection dialed in) that the client answers '
            'with CHANNEL_CLOSE instead of a confirmation — the pending-open '
            'race; then a control connection confirmed properly',
        citation:
            'channels.c:channel_post_port_listener (the accepted socket is '
            'the new channel\'s fd) + nchan.c:chan_rcvd_oclose (the OPENING '
            'channel tears down; the fds close — the dialed-in connection is '
            'reset) vs server_connection.dart:_handleChannelOpenReply (only '
            'CONFIRMATION / OPEN_FAILURE resolve a pending open; a CLOSE '
            'addressed to it falls through _channelOrNull -> null and is '
            'dropped, the accepted connection is held forever)',
        predicted: 'sshd: the CLOSE tears the pending channel down — the '
            'dialed-in TCP connection is closed by the server (and a CLOSE echo '
            'may come back). tp_sshd: the CLOSE is silently dropped, the '
            'dialed-in connection is never closed (the pending open leaks until '
            'the connection ends); the control connection works on both',
        probe: _probeD08,
      ),
      row(
        id: 'D09',
        stimulus:
            'a pty session (pty-req + shell) exited by typing `exit`: the '
            'exit-status / EOF / CLOSE ordering with the pty teardown',
        citation: 'session.c:session_close_by_pid (exit-status via '
            'session_exit_message, then session_pty_cleanup releases the tty) + '
            'nchan.c:chan_send_eof2/chan_send_close2 vs server_session.dart:'
            '_pipeProcess (pty process exit -> sendExitStatus -> close; the '
            'harness pty is util-linux `script`)',
        predicted: 'both servers: shell output, then exit-status(0), then EOF, '
            'then CLOSE; the channel finishes promptly (the pty is released '
            'with it)',
        probe: _probeD09,
      ),
      row(
        id: 'D10',
        stimulus: 'a `signal` channel request with a bogus signal name '
            '(SIGBOGUS), want_reply = true, on a `sleep 30` exec channel',
        citation: 'session.c:session_input_channel_req -> session.c:'
            'session_signal_req (name2sig fails -> error "unsupported signal" '
            '-> success 0 -> CHANNEL_FAILURE) vs server_session.dart:'
            '_handleSignalRequest (no live pty on an exec channel -> refused -> '
            'CHANNEL_FAILURE)',
        predicted: 'both servers answer CHANNEL_FAILURE; connection stays open',
        probe: _probeD10,
      ),
    ];

// ---------------------------------------------------------------------------
// D01–D10 probes
// ---------------------------------------------------------------------------

Future<String> _probeD01(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    final confirmation = await openSessionChannel(session, senderChannel: 100);
    final serverChannel = confirmation.senderChannel;
    // `cat > /dev/null; sleep 30`: the cat half swallows the pre-EOF data,
    // and the sleep half keeps the process (and so the channel) alive after
    // the client's EOF — the post-EOF data lands on a LIVE channel, which
    // is the race the row is about.
    await requestExec(
      session,
      serverChannel,
      'cat > /dev/null; sleep 30',
      since: baseline,
    );
    session.transport!.sendPacket(
      SSH_Message_Channel_Data(
        recipientChannel: serverChannel,
        data: Uint8List.fromList('hello\n'.codeUnits),
      ).encode(),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final afterHello = (await snapshot(session)).length;
    // The stimulus: EOF, then more data on the same channel.
    session.transport!.sendPacket(
      SSH_Message_Channel_EOF(recipientChannel: serverChannel).encode(),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    session.transport!.sendPacket(
      SSH_Message_Channel_Data(
        recipientChannel: serverChannel,
        data: Uint8List.fromList('after-eof\n'.codeUnits),
      ).encode(),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    final slice = (await snapshot(session)).skip(afterHello).toList();
    final closed = slice.any((o) => o is ClosedObservation);
    return 'after client EOF + 10 more data bytes on the live channel: '
        '${describePostAuth(slice)}; connection '
        '${closed ? 'CLOSED (torn down)' : 'open'}';
  } finally {
    await session.close();
  }
}

Future<String> _probeD02(AuditServers servers, int port) async {
  // Phase 1: the client CLOSEs while ~252 KiB of output is stuck for
  // window credit.
  final phase1 = await _d02Phase1(servers, port);
  // Phase 2: the server-side exit under the same pressure.
  final phase2 = await _d02Phase2(servers, port);
  return 'phase 1 (client CLOSE, output pending credit): $phase1; '
      'phase 2 (server exit, output pending credit): $phase2';
}

Future<String> _d02Phase1(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    final confirmation = await openSessionChannel(
      session,
      senderChannel: 100,
      clientWindow: 4096,
    );
    final serverChannel = confirmation.senderChannel;
    await requestExec(
      session,
      serverChannel,
      'head -c 262144 /dev/zero',
      since: baseline,
    );
    final afterExec = (await snapshot(session)).length;
    // 4000, not 4096: sshd's exec emits ~45 bytes of shell-startup stderr
    // (the harness user's rc runs tput without TERM), and EXTENDED data
    // counts against the same window.
    await awaitObservation(
      session,
      (slice) => receivedDataBytes(slice) >= 4000,
      what: 'the window-sized first burst (~4096 bytes)',
      since: afterExec,
      timeout: const Duration(seconds: 5),
    );
    final afterBurst = (await snapshot(session)).length;
    session.transport!.sendPacket(
      SSH_Message_Channel_Close(recipientChannel: serverChannel).encode(),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    final slice = (await snapshot(session)).skip(afterBurst).toList();
    final closedBack = slice.any(
      (o) =>
          o is MessageObservation &&
          o.id == SSH_Message_Channel_Close.messageId,
    );
    return 'server sent ${receivedDataBytes(slice)} more data bytes, '
        '${closedBack ? 'CHANNEL_CLOSE (channel finished)' : 'NOTHING (no '
            'CLOSE back — the channel is held)'}; sequence: '
        '${_describeTeardown(slice)}';
  } finally {
    await session.close();
  }
}

Future<String> _d02Phase2(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    final confirmation = await openSessionChannel(
      session,
      senderChannel: 100,
      clientWindow: 4096,
    );
    final serverChannel = confirmation.senderChannel;
    await requestExec(
      session,
      serverChannel,
      'head -c 262144 /dev/zero',
      since: baseline,
    );
    final afterExec = (await snapshot(session)).length;
    // 4000, not 4096: sshd's shell-startup stderr costs ~45 window bytes
    // (see phase 1).
    await awaitObservation(
      session,
      (slice) => receivedDataBytes(slice) >= 4000,
      what: 'the window-sized first burst (~4096 bytes)',
      since: afterExec,
      timeout: const Duration(seconds: 5),
    );
    // No client close: wait for the process to exit and report itself.
    var exitStatusSeen = false;
    try {
      await awaitMessage(
        session,
        const [SSH_Message_Channel_Request.messageId],
        since: afterExec,
        timeout: const Duration(seconds: 10),
      );
      exitStatusSeen = true;
    } on TimeoutException {
      exitStatusSeen = false;
    }
    if (!exitStatusSeen) {
      return 'exit-status never arrived within 10 s';
    }
    final atExitStatus = DateTime.now();
    var closed = false;
    try {
      await awaitMessage(
        session,
        const [SSH_Message_Channel_Close.messageId],
        since: afterExec,
        timeout: const Duration(seconds: 10),
      );
      closed = true;
    } on TimeoutException {
      closed = false;
    }
    final delay = DateTime.now().difference(atExitStatus).inMilliseconds;
    final slice = (await snapshot(session)).skip(afterExec).toList();
    final eofSeen = slice.any(
      (o) =>
          o is MessageObservation && o.id == SSH_Message_Channel_EOF.messageId,
    );
    return 'exit-status arrived, then '
        '${eofSeen ? 'EOF, ' : 'NO EOF, '}'
        '${closed ? 'CLOSE' : 'no CLOSE'} '
        '${delay} ms later; ${receivedDataBytes(slice)} data bytes total '
        '(the pending tail was '
        '${receivedDataBytes(slice) > 4096 ? 'partly flushed' : 'dropped'})';
  } finally {
    await session.close();
  }
}

/// Renders one exec channel's teardown slice: data volume, then the
/// exit-status value, then EOF/CLOSE, in arrival order.
String _describeTeardown(List<Observed> observations) {
  final parts = <String>[];
  final data = receivedDataBytes(observations);
  if (data > 0) parts.add('data:$data bytes');
  for (final observation in observations) {
    if (observation is! MessageObservation) continue;
    switch (observation.id) {
      case SSH_Message_Channel_Request.messageId:
        if (observation.payload != null) {
          try {
            final request = SSH_Message_Channel_Request.decode(
              observation.payload!,
            );
            if (request.exitStatus != null) {
              parts.add('exit-status(${request.exitStatus})');
              continue;
            }
            parts.add('request:${request.requestType}');
            continue;
          } on Object {
            // Fall through to the generic rendering below.
          }
        }
        parts.add(observation.toString());
      case SSH_Message_Channel_EOF.messageId:
        parts.add('EOF');
      case SSH_Message_Channel_Close.messageId:
        parts.add('CLOSE');
      case SSH_Message_Channel_Success.messageId:
        parts.add('CHANNEL_SUCCESS');
      case SSH_Message_Channel_Window_Adjust.messageId:
        // Window adjusts are not part of the teardown ordering story.
        break;
      default:
        if (observation.id != SSH_Message_Channel_Data.messageId &&
            observation.id != SSH_Message_Global_Request.messageId &&
            observation.id != SSH_Message_Debug.messageId) {
          parts.add(observation.toString());
        }
    }
  }
  return parts.join(' -> ');
}

Future<String> _probeD03(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    final confirmation = await openSessionChannel(session, senderChannel: 100);
    final serverChannel = confirmation.senderChannel;
    await requestExec(session, serverChannel, 'echo done', since: baseline);
    // The client half-closes immediately: both sides will have EOF'd.
    session.transport!.sendPacket(
      SSH_Message_Channel_EOF(recipientChannel: serverChannel).encode(),
    );
    await Future<void>.delayed(const Duration(seconds: 3));
    final slice = (await snapshot(session)).skip(baseline).toList();
    final serverClosed = slice.any(
      (o) =>
          o is MessageObservation &&
          o.id == SSH_Message_Channel_Close.messageId,
    );
    return 'client sent EOF only (never CLOSE); server sequence: '
        '${_describeTeardown(slice)}; CHANNEL_CLOSE from server: '
        '${serverClosed ? 'yes' : 'no'}';
  } finally {
    await session.close();
  }
}

Future<String> _probeD04(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    final confirmation = await openSessionChannel(session, senderChannel: 100);
    final serverChannel = confirmation.senderChannel;
    await requestExec(session, serverChannel, 'echo ok', since: baseline);
    // The client never EOFs: everything that follows is the server's own
    // teardown.
    await Future<void>.delayed(const Duration(seconds: 3));
    final slice = (await snapshot(session)).skip(baseline).toList();
    return 'no client EOF; server sequence: ${_describeTeardown(slice)}';
  } finally {
    await session.close();
  }
}

Future<String> _probeD05(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    final confirmation = await openSessionChannel(session, senderChannel: 100);
    final serverChannel = confirmation.senderChannel;
    await requestExec(session, serverChannel, 'echo ok', since: baseline);
    // Wait for the server to finish the channel completely.
    await awaitMessage(
      session,
      const [SSH_Message_Channel_Close.messageId],
      since: baseline,
    );
    final atClose = (await snapshot(session)).length;
    // Acknowledge the close, then let the server settle (sshd frees the
    // channel on a later pass), then fire the racing request.
    session.transport!.sendPacket(
      SSH_Message_Channel_Close(recipientChannel: serverChannel).encode(),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    session.transport!.sendPacket(
      SSH_Message_Channel_Request.env(
        recipientChannel: serverChannel,
        wantReply: true,
        variableName: 'TP_DIFF',
        variableValue: 'd05',
      ).encode(),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    final slice = (await snapshot(session)).skip(atClose).toList();
    return await withSshdLogCheck(
      servers,
      port,
      'CHANNEL_REQUEST after the channel fully closed: '
          '${describePostAuth(slice)}',
      'unknown channel',
    );
  } finally {
    await session.close();
  }
}

Future<String> _probeD06(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    final confirmation = await openSessionChannel(session, senderChannel: 100);
    final serverChannel = confirmation.senderChannel;
    await requestExec(
      session,
      serverChannel,
      'head -c 1048576 /dev/zero',
      since: baseline,
    );
    // Let the stream actually be in flight, then kill the socket hard.
    await awaitObservation(
      session,
      (slice) => receivedDataBytes(slice) >= 65536,
      what: '64 KiB of the exec stream',
      since: baseline,
      timeout: const Duration(seconds: 5),
    );
    final inFlight = receivedDataBytes(
      (await snapshot(session)).skip(baseline).toList(),
    );
    session.destroyAbruptly();
    await Future<void>.delayed(const Duration(seconds: 1));
    return await withSshdLogCheckAny(
      servers,
      port,
      'client sent an RST mid-channel ($inFlight bytes received, stream '
      'still flowing); the runner\'s listener check below is the survival '
      'observable, and the runner\'s zone reports any leaked async error '
      'on the tp_sshd side',
      const ['Connection reset', 'Connection closed', 'Read error'],
    );
  } finally {
    await session.close();
  }
}

Future<String> _probeD07(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    final confirmation = await openSessionChannel(session, senderChannel: 100);
    final serverChannel = confirmation.senderChannel;
    await requestExec(session, serverChannel, 'sleep 2', since: baseline);
    final afterExec = (await snapshot(session)).length;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    // CLOSE without any EOF, while the child is still running.
    session.transport!.sendPacket(
      SSH_Message_Channel_Close(recipientChannel: serverChannel).encode(),
    );
    await Future<void>.delayed(const Duration(seconds: 5));
    final slice = (await snapshot(session)).skip(afterExec).toList();
    final closeEcho = slice
        .where(
          (o) =>
              o is MessageObservation &&
              o.id == SSH_Message_Channel_Close.messageId,
        )
        .length;
    // When did the CLOSE echo land (immediately vs at child exit)?
    String timing = 'no CLOSE echo at all';
    if (closeEcho > 0) {
      // The probe cannot timestamp observations; the gap is inferred from
      // whether anything else (exit-status) preceded the close.
      final exitStatus = slice.any(
        (o) =>
            o is MessageObservation &&
            o.id == SSH_Message_Channel_Request.messageId,
      );
      timing =
          'CLOSE echoed ${exitStatus ? 'after exit-status (at child exit)' : 'immediately (before any exit-status)'}';
    }
    return 'client CLOSE, no EOF, child still running: '
        '${_describeTeardown(slice)}; $timing';
  } finally {
    await session.close();
  }
}

Future<String> _probeD08(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  Socket? controlSocket;
  try {
    // Ask the server to listen on an ephemeral loopback port for us.
    session.transport!.sendPacket(
      SSH_Message_Global_Request.tcpipForward('127.0.0.1', 0).encode(),
    );
    await awaitMessage(
      session,
      const [SSH_Message_Request_Success.messageId],
      since: baseline,
    );
    final successMessage = latestMessage(
      session,
      const [SSH_Message_Request_Success.messageId],
      since: baseline,
    );
    if (successMessage?.payload == null) {
      return 'tcpip-forward was not granted '
          '(${describePostAuth((await snapshot(session)).skip(baseline).toList())})';
    }
    // The success payload is the actually-bound port (a uint32); the
    // observation payload carries the message id byte first.
    final requestData = SSH_Message_Request_Success.decode(
      successMessage!.payload!,
    ).requestData;
    final boundPort = requestData.length >= 4
        ? ByteData.sublistView(requestData, 0, 4).getUint32(0)
        : 0;

    // Dial in: the server must open a forwarded-tcpip channel at us.
    final probeSocket = await Socket.connect('127.0.0.1', boundPort);
    // Watching for the server to close our connection: the stream's onDone
    // fires when the peer tears the socket down.
    final serverClosed = Completer<void>();
    final probeSubscription = probeSocket.listen(
      (Uint8List _) {},
      onError: (Object _) {},
      onDone: () {
        if (!serverClosed.isCompleted) serverClosed.complete();
      },
    );
    try {
      await awaitMessage(
        session,
        const [SSH_Message_Channel_Open.messageId],
        since: baseline,
        timeout: const Duration(seconds: 5),
      );
      final open = latestServerChannelOpen(session, since: baseline);
      if (open == null) {
        return 'no forwarded-tcpip CHANNEL_OPEN arrived';
      }
      final pendingChannel = open.senderChannel;
      final atOpen = (await snapshot(session)).length;

      // The stimulus: answer the pending open with CLOSE, not a verdict.
      session.transport!.sendPacket(
        SSH_Message_Channel_Close(recipientChannel: pendingChannel).encode(),
      );
      // Did the server tear the forwarded connection down?
      var probeClosedByServer = false;
      try {
        await serverClosed.future.timeout(const Duration(seconds: 2));
        probeClosedByServer = true;
      } on TimeoutException {
        probeClosedByServer = false;
      }
      final slice = (await snapshot(session)).skip(atOpen).toList();

      // Control: a second connection, confirmed properly, must round-trip
      // one byte (socket -> forwarded channel -> socket).
      var control = '(not run)';
      controlSocket = await Socket.connect('127.0.0.1', boundPort);
      try {
        await awaitMessage(
          session,
          const [SSH_Message_Channel_Open.messageId],
          since: atOpen,
          timeout: const Duration(seconds: 5),
        );
        final controlOpen = latestServerChannelOpen(session, since: atOpen);
        if (controlOpen == null) {
          control = 'no second forwarded-tcpip open arrived';
        } else {
          session.transport!.sendPacket(
            SSH_Message_Channel_Confirmation(
              recipientChannel: controlOpen.senderChannel,
              senderChannel: 400,
              initialWindowSize: 65536,
              maximumPacketSize: 32768,
              data: Uint8List(0),
            ).encode(),
          );
          // One byte in on the TCP side must come back as CHANNEL_DATA.
          controlSocket.add(Uint8List.fromList('x'.codeUnits));
          var echoed = false;
          try {
            await awaitObservation(
              session,
              (observations) => receivedDataBytes(observations) >= 1,
              what: 'the control echo',
              since: atOpen,
              timeout: const Duration(seconds: 5),
            );
            echoed = true;
          } on TimeoutException {
            echoed = false;
          }
          control = echoed
              ? 'echoed (forwarding alive)'
              : 'no echo (forwarding broken)';
        }
      } finally {
        controlSocket.destroy();
      }
      return 'pending forwarded-tcpip answered with CLOSE: '
          '${describePostAuth(slice)}; dialed-in connection '
          '${probeClosedByServer ? 'closed by the server (torn down)' : 'still open (held — leak)'}; '
          'control connection: $control';
    } finally {
      await probeSubscription.cancel();
      probeSocket.destroy();
    }
  } finally {
    controlSocket?.destroy();
    await session.close();
  }
}

Future<String> _probeD09(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    final confirmation = await openSessionChannel(session, senderChannel: 100);
    final serverChannel = confirmation.senderChannel;
    // pty-req, then shell: the pty session the harness serves.
    session.transport!.sendPacket(
      SSH_Message_Channel_Request.pty(
        recipientChannel: serverChannel,
        wantReply: true,
        termType: 'xterm-256color',
        termWidth: 80,
        termHeight: 24,
        termPixelWidth: 0,
        termPixelHeight: 0,
        termModes: Uint8List(0),
      ).encode(),
    );
    await awaitMessage(
      session,
      const [SSH_Message_Channel_Success.messageId],
      since: baseline,
    );
    final afterPty = (await snapshot(session)).length;
    session.transport!.sendPacket(
      SSH_Message_Channel_Request.shell(
        recipientChannel: serverChannel,
        wantReply: true,
      ).encode(),
    );
    await awaitMessage(
      session,
      const [SSH_Message_Channel_Success.messageId],
      since: afterPty,
    );
    // Wait for the shell to actually start (its first output), then exit.
    await awaitMessage(
      session,
      const [SSH_Message_Channel_Data.messageId],
      since: afterPty,
      timeout: const Duration(seconds: 5),
    );
    final afterShellOutput = (await snapshot(session)).length;
    session.transport!.sendPacket(
      SSH_Message_Channel_Data(
        recipientChannel: serverChannel,
        data: Uint8List.fromList('exit\r\n'.codeUnits),
      ).encode(),
    );
    await Future<void>.delayed(const Duration(seconds: 5));
    final slice = (await snapshot(session)).skip(afterShellOutput).toList();
    return 'pty session, `exit` typed: ${_describeTeardown(slice)}';
  } finally {
    await session.close();
  }
}

Future<String> _probeD10(AuditServers servers, int port) async {
  final (session, baseline) = await dialPostAuth(servers, port);
  try {
    final confirmation = await openSessionChannel(session, senderChannel: 100);
    final serverChannel = confirmation.senderChannel;
    await requestExec(session, serverChannel, 'sleep 30', since: baseline);
    final afterExec = (await snapshot(session)).length;
    // A signal request with a name no signal table knows, want_reply true
    // so the refusal is observable.
    session.transport!.sendPacket(
      SSH_Message_Channel_Request(
        recipientChannel: serverChannel,
        requestType: SSHChannelRequestType.signal,
        wantReply: true,
        signalName: 'SIGBOGUS',
      ).encode(),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    final slice = (await snapshot(session)).skip(afterExec).toList();
    return await withSshdLogCheck(
      servers,
      port,
      'signal SIGBOGUS on a `sleep 30` exec: ${describePostAuth(slice)}',
      'unsupported signal',
    );
  } finally {
    await session.close();
  }
}
