import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' show SSHSocket, SSHTransport;
import 'package:dartssh2/protocol.dart';

import 'server_channel.dart';
import 'server_dial.dart';
import 'server_forward.dart';
import 'server_session.dart';
import 'server_userauth.dart';
import 'ssh_server.dart'
    show SSHServerAuthRequest, SSHServerConfig, tpServerAlgorithms;

/// Lifecycle phases of an [SSHServerConnection].
enum _Phase {
  /// Handshake done; the client is trying to authenticate. Everything except
  /// the service negotiation and userauth is refused.
  auth,

  /// Authenticated; session traffic (channels) is served. Reached when a
  /// signed `publickey` userauth request both verified and was trusted.
  running,

  /// The connection is gone.
  closed,
}

/// One accepted connection: a server-role [SSHTransport] plus the
/// connection-level state machine, the publickey userauth service, and the
/// auth timeout that bounds the pre-authentication phase.
class SSHServerConnection {
  SSHServerConnection(
    this.socket, {
    required SSHServerConfig config,
  }) : _config = config {
    // SSHTransport takes its handlers as final constructor-injected fields,
    // so the state machine has to be wired in right here.
    _transport = SSHTransport(
      socket,
      isServer: true,
      hostKeyPair: config.hostKeyPair,
      algorithms: tpServerAlgorithms,
      printDebug: config.printDebug,
      printTrace: config.printTrace,
      onMessage: _handleMessage,
    );
    _authTimer = Timer(config.authTimeout, _onAuthTimeout);
    final forwarding = config.forwarding;
    if (forwarding != null) {
      final targetAllowed = forwarding.permitOpen == null
          ? (String host, int port) async => true
          : (String host, int port) async =>
              forwarding.permitOpen!(this, host, port);
      _forwarder = SSHServerForwarder(
        allowTcpForwarding: forwarding.allowTcpForwarding,
        allowTarget: targetAllowed,
        bindServerSocket: forwarding.bindServerSocket,
        openForwardedChannel: _openForwardedChannel,
        sendPacket: _sendPacket,
        printDebug: config.printDebug,
      );
    } else {
      _forwarder = null;
    }
    // The transport's done future completes with an error when the transport
    // is terminated by one; the connection only cares about the timing.
    _transport.done.whenComplete(_onTransportClosed).ignore();
  }

  /// The socket this connection serves.
  final SSHSocket socket;

  final SSHServerConfig _config;

  late final SSHTransport _transport;
  late final Timer _authTimer;
  late final SSHServerForwarder? _forwarder;
  var _phase = _Phase.auth;

  /// Open channels on this connection, keyed by the server-assigned channel
  /// number (the id the client addresses them by).
  final _channels = <int, SSHServerChannel>{};

  /// Channel ids this server finished whose CHANNEL_CLOSE the client has
  /// not sent yet. A message addressed to one of these raced our close —
  /// the client could not have seen it yet — so it is tolerated the way
  /// sshd's still-allocated dying channels tolerate it, until the client's
  /// own CHANNEL_CLOSE moves the id to [_reapedChannels].
  final _closingChannels = <int>{};

  /// Channel ids whose close handshake completed on both sides. A message
  /// for one of these is a protocol error, exactly like sshd's
  /// channel_from_packet_id against a freed channel.
  final _reapedChannels = <int>{};

  /// Server-initiated channel opens awaiting the client's verdict, keyed by
  /// the channel number the open was sent with (see [_openServerChannel]).
  final _pendingOpens = <int, _PendingOpen>{};

  /// The next channel number to assign. A plain counter is enough: channel
  /// numbers are only reused after 2^32 opens.
  var _nextChannelNumber = 0;

  /// Failed authentication attempts so far, for the
  /// [SSHServerConfig.maxAuthAttempts] throttle.
  var _authAttempts = 0;

  /// Whether the client completed the `ssh-userauth` service negotiation
  /// (RFC 4253 §10). sshd only registers its USERAUTH_REQUEST handler once
  /// the service is accepted (auth2.c:do_authentication2 +
  /// input_service_request), so a request before that falls to the default
  /// dispatch and is answered with UNIMPLEMENTED — never processed, never
  /// answered with USERAUTH_PK_OK, never authenticating.
  var _serviceAccepted = false;

  /// How many key exchanges this connection initiated on its own — the
  /// rekey trigger ([SSHServerConfig.rekeyBytes]/[rekeyInterval]) firing,
  /// not a peer-initiated exchange. Read-only, for tests and embedder
  /// diagnostics.
  int get rekeyCount => _rekeyCount;
  var _rekeyCount = 0;

  /// Outbound bytes counted since the last key exchange this server
  /// initiated completed, checked on every send against
  /// [SSHServerConfig.rekeyBytes] (sshd's `rekey bytes` accounting,
  /// packet.c:1095-1097).
  var _outboundBytes = 0;

  /// The one-shot timer for [SSHServerConfig.rekeyInterval], armed when the
  /// connection authenticates and re-armed after every completed exchange.
  Timer? _rekeyTimer;

  /// Whether a server-initiated key exchange is still in flight, so
  /// concurrent threshold crossings (a byte threshold hit mid-exchange, the
  /// timer firing during an exchange) collapse into the one exchange
  /// already running.
  var _rekeyInFlight = false;

  /// Completes when the underlying transport closes, normally or with an
  /// error.
  Future<void> get done => _transport.done;

  /// The channels currently open on this connection, keyed by the
  /// server-assigned channel number.
  Map<int, SSHServerChannel> get channels => Map.unmodifiable(_channels);

  /// Closes the connection and its socket.
  Future<void> close() async {
    _authTimer.cancel();
    _rekeyTimer?.cancel();
    _phase = _Phase.closed;
    _teardownChannels();
    await _forwarder?.close();
    await _transport.close();
  }

  /// The connection's outbound send path: every packet the connection layer
  /// emits — its own replies and every channel's and the forwarder's
  /// traffic — goes through here, so the rekey accounting sees it (audit
  /// B06/B07: without a byte counter and a timer, a long-lived pairing
  /// session keeps its keys forever).
  void _sendPacket(Uint8List data) {
    _transport.sendPacket(data);
    _countOutbound(data.length);
  }

  /// Counts [bytes] of outbound traffic against
  /// [SSHServerConfig.rekeyBytes], initiating a rekey when the threshold is
  /// crossed. Bytes sent while an exchange is in flight are not counted:
  /// the counter resets to zero when that exchange completes anyway.
  void _countOutbound(int bytes) {
    if (_phase != _Phase.running || _rekeyInFlight) return;
    final rekeyBytes = _config.rekeyBytes;
    if (rekeyBytes == null) return;
    _outboundBytes += bytes;
    if (_outboundBytes >= rekeyBytes) {
      _startRekey('$_outboundBytes bytes sent');
    }
  }

  /// Arms the one-shot [SSHServerConfig.rekeyInterval] timer.
  void _armRekeyTimer() {
    _rekeyTimer?.cancel();
    final interval = _config.rekeyInterval;
    if (interval == null || _phase != _Phase.running) return;
    _rekeyTimer = Timer(interval, () => _startRekey('interval elapsed'));
  }

  /// Initiates a key exchange of our own (sshd's `kex_start_rekex`,
  /// packet.c:1070-1123): an unprompted KEXINIT goes out through the
  /// transport's [SSHTransport.rekey], and the byte counter and interval
  /// deadline restart once the exchange completes. Concurrent triggers
  /// collapse into the exchange already in flight.
  void _startRekey(String why) {
    if (_phase != _Phase.running || _rekeyInFlight) return;
    _rekeyInFlight = true;
    _rekeyCount += 1;
    _config.printDebug?.call('tp_sshd: initiating rekey ($why)');
    _transport
        .rekey()
        .whenComplete(() {
          // The connection may have ended before the exchange completed;
          // nothing is re-armed then.
          if (_phase != _Phase.running) return;
          _rekeyInFlight = false;
          _outboundBytes = 0;
          _armRekeyTimer();
        })
        .ignore();
  }

  /// Auth-phase message handling.
  ///
  /// Returns whether the message was recognized, so the transport answers
  /// unrecognized ones with SSH_MSG_UNIMPLEMENTED (RFC 4253 §11).
  bool _handleMessage(Uint8List payload) {
    switch (_phase) {
      case _Phase.closed:
        return false;
      case _Phase.auth:
        return _handleAuthMessage(payload);
      case _Phase.running:
        return _handleRunningMessage(payload);
    }
  }

  bool _handleAuthMessage(Uint8List payload) {
    switch (SSHMessage.readMessageId(payload)) {
      case SSH_Message_Service_Request.messageId:
        final message = SSH_Message_Service_Request.decode(payload);
        if (message.serviceName == 'ssh-userauth') {
          _serviceAccepted = true;
          _sendPacket(
            SSH_Message_Service_Accept(message.serviceName).encode(),
          );
        } else {
          _disconnect(
            SSHDisconnectReason.serviceNotAvailable,
            'Service not available: ${message.serviceName}',
          );
        }
        return true;
      case SSH_Message_Userauth_Request.messageId:
        if (!_serviceAccepted) {
          // Not negotiated yet: sshd's default dispatch answers
          // UNIMPLEMENTED (audit A08), and the connection stays open.
          return false;
        }
        // The trust decision is the embedder's async authenticate callback,
        // so the request is handled detached from the synchronous
        // onMessage dispatch.
        unawaited(_handleUserauthRequest(payload));
        return true;
      default:
        // Unrecognized message: let the transport answer with
        // SSH_MSG_UNIMPLEMENTED.
        return false;
    }
  }

  /// Running-phase message handling (RFC 4254): channel multiplexing and
  /// global requests.
  ///
  /// Returns whether the message was recognized, so the transport answers
  /// unrecognized ones with SSH_MSG_UNIMPLEMENTED (RFC 4253 §11).
  bool _handleRunningMessage(Uint8List payload) {
    switch (SSHMessage.readMessageId(payload)) {
      case SSH_Message_Global_Request.messageId:
        _handleGlobalRequest(payload);
        return true;
      case SSH_Message_Channel_Open.messageId:
        _handleChannelOpen(payload);
        return true;
      case SSH_Message_Channel_Confirmation.messageId:
      case SSH_Message_Channel_Open_Failure.messageId:
        _handleChannelOpenReply(payload);
        return true;
      case SSH_Message_Channel_Window_Adjust.messageId:
      case SSH_Message_Channel_Data.messageId:
      case SSH_Message_Channel_Extended_Data.messageId:
      case SSH_Message_Channel_EOF.messageId:
      case SSH_Message_Channel_Close.messageId:
      case SSH_Message_Channel_Request.messageId:
        _handleChannelMessage(payload);
        return true;
      default:
        return false;
    }
  }

  /// Answers global requests (RFC 4254 §4). `keepalive` is acknowledged,
  /// and `tcpip-forward` / `cancel-tcpip-forward` are handed to the
  /// forwarder, which replies asynchronously once the injected bind settles.
  /// Everything else — including forwarding when no forwarding config is
  /// configured — is refused.
  void _handleGlobalRequest(Uint8List payload) {
    final message = _decodeMessage(
      'global request',
      SSH_Message_Global_Request.decode,
      payload,
    );
    if (message == null) return;
    switch (message.requestName) {
      case 'tcpip-forward':
      case 'cancel-tcpip-forward':
        final forwarder = _forwarder;
        if (forwarder != null) {
          unawaited(forwarder.handleGlobalRequest(message));
          return;
        }
      // No seam configured: this case body ends here, and control continues
      // after the switch to the shared wantReply refusal below.
      case 'keepalive@openssh.com':
        if (message.wantReply) {
          _sendPacket(
            SSH_Message_Request_Success(Uint8List(0)).encode(),
          );
        }
        return;
    }
    if (message.wantReply) {
      _sendPacket(SSH_Message_Request_Failure().encode());
    }
  }

  /// Serves CHANNEL_OPEN (RFC 4254 §5.1): distinguishes by channel type, and
  /// applies the per-connection channel cap before the type dispatch so every
  /// kind of open — `session` and `direct-tcpip` alike — counts against the
  /// same quota.
  ///
  /// - `session` channels are confirmed with a fresh [SSHServerChannel].
  /// - `direct-tcpip` opens (RFC 4254 §7.1) are served by the direct dialer:
  ///   gated by the forwarding config, then dialed through the injected seam;
  ///   the outcome is replied asynchronously (see [_serveDirectTcpip]).
  /// - Every other type — `x11`, `direct-streamlocal@openssh.com`, …
  ///   (server-initiated opens — the outbound direction, used for
  ///   `forwarded-tcpip` — go through [_openServerChannel] instead) — is
  ///   refused with reason 1, `codeAdministrativelyProhibited`. The named
  ///   constant for that semantic wins per the controller ruling that real
  ///   fork API names take precedence; reason 3 (`codeUnknownChannelType`)
  ///   would be the wrong semantic for a recognized-but-unserved type.
  void _handleChannelOpen(Uint8List payload) {
    final message = _decodeMessage(
      'channel open',
      SSH_Message_Channel_Open.decode,
      payload,
    );
    if (message == null) return;

    // The per-connection channel cap (OpenSSH's default is 10): without it,
    // one connection could pin unbounded channel state on the server. Excess
    // opens are refused with reason 4, resource shortage (RFC 4254 §5.1's
    // "channel resource shortage" case), before the type dispatch so a
    // direct-tcpip open cannot evade its half of the quota.
    if (_channels.length >= _config.maxChannels) {
      _sendPacket(
        SSH_Message_Channel_Open_Failure(
          recipientChannel: message.senderChannel,
          reasonCode: SSH_Message_Channel_Open_Failure.codeResourceShortage,
          description: 'Too many open channels (${_channels.length}/'
              '${_config.maxChannels})',
        ).encode(),
      );
      return;
    }

    if (message.channelType == 'direct-tcpip') {
      unawaited(_serveDirectTcpip(message));
      return;
    }

    if (message.channelType != 'session') {
      _sendPacket(
        SSH_Message_Channel_Open_Failure(
          recipientChannel: message.senderChannel,
          reasonCode:
              SSH_Message_Channel_Open_Failure.codeAdministrativelyProhibited,
          description: "Channel type '${message.channelType}' is not supported",
        ).encode(),
      );
      return;
    }

    final ourChannel = _nextChannelNumber++;
    final channel = SSHServerChannel(
      recipientChannel: message.senderChannel,
      ourChannel: ourChannel,
      channelType: message.channelType,
      peerInitialWindowSize: message.initialWindowSize,
      peerMaximumPacketSize: message.maximumPacketSize,
      sendPacket: _sendPacket,
      onClosed: _onChannelClosed,
      onProtocolViolation: _disconnectForChannelViolation,
      printDebug: _config.printDebug,
    );
    // Session requests (exec today; shell and pty in Task 7) are served by
    // the session layer. The handler refuses everything it does not serve.
    channel.onRequest = (channel, request) =>
        handleSessionRequest(channel, request, config: _config);
    _channels[ourChannel] = channel;
    _sendPacket(
      SSH_Message_Channel_Confirmation(
        recipientChannel: message.senderChannel,
        senderChannel: ourChannel,
        initialWindowSize: SSHServerChannel.initialReceiveWindow,
        maximumPacketSize: SSHServerChannel.maximumPacketSize,
        data: Uint8List(0),
      ).encode(),
    );
  }

  /// Serves one `direct-tcpip` channel open (RFC 4254 §7.1): gates it against
  /// the forwarding config through [SSHServerDirectDialer], then either
  /// refuses it with the dialer's reason or confirms the channel and rides
  /// the dialed connection on the shared forward pump.
  ///
  /// The dial is asynchronous — the embedded dial seam may resolve a host and
  /// connect — so the reply is sent from this detached future, never from the
  /// transport's synchronous dispatch. A connection that closes while the
  /// dial is in flight is torn down without a reply: the dialed socket is
  /// destroyed and nothing is sent.
  Future<void> _serveDirectTcpip(SSH_Message_Channel_Open message) async {
    final forwarding = _config.forwarding;
    if (forwarding == null || message.host == null || message.port == null) {
      _refuseChannelOpen(
        message.senderChannel,
        SSH_Message_Channel_Open_Failure.codeAdministrativelyProhibited,
        'TCP forwarding is disabled',
      );
      return;
    }
    // The originator endpoint is informational only (RFC 4254 §7.1), but
    // OpenSSH refuses a wire port above 0xFFFF with reason 1 before dialing
    // (serverloop.c); keep the same bound so the refusal precedes any dial.
    final originatorPort = message.originatorPort;
    if (originatorPort != null && originatorPort > 0xFFFF) {
      _refuseChannelOpen(
        message.senderChannel,
        SSH_Message_Channel_Open_Failure.codeAdministrativelyProhibited,
        'invalid originator port',
      );
      return;
    }
    final dialer = SSHServerDirectDialer(
      forwarding: forwarding,
      allowTarget: _directTargetAllowed,
    );
    final result = await dialer.dial(message.host!, message.port!);
    switch (result) {
      case DirectDialRefused():
        _refuseChannelOpen(
            message.senderChannel, result.reasonCode, result.description);
      case DirectDialConnected():
        // Connection closed while dialing: destroy the dialed socket and send
        // nothing.
        if (_phase != _Phase.running) {
          result.connection.destroy();
          return;
        }
        // The channel cap may have been crossed while dialing: the receive-time
        // re-check already admitted concurrent in-flight dials, and this
        // re-check before registration blocks the race (the same re-check
        // OpenSSH does after channel_new).
        if (_channels.length >= _config.maxChannels) {
          result.connection.destroy();
          _refuseChannelOpen(
            message.senderChannel,
            SSH_Message_Channel_Open_Failure.codeResourceShortage,
            'Too many open channels',
          );
          return;
        }
        final ourChannel = _nextChannelNumber++;
        final channel = SSHServerChannel(
          recipientChannel: message.senderChannel,
          ourChannel: ourChannel,
          channelType: 'direct-tcpip',
          peerInitialWindowSize: message.initialWindowSize,
          peerMaximumPacketSize: message.maximumPacketSize,
          sendPacket: _sendPacket,
          onClosed: _onChannelClosed,
          onProtocolViolation: _disconnectForChannelViolation,
          printDebug: _config.printDebug,
        );
        _channels[ourChannel] = channel;
        _sendPacket(
          SSH_Message_Channel_Confirmation(
            recipientChannel: message.senderChannel,
            senderChannel: ourChannel,
            initialWindowSize: SSHServerChannel.initialReceiveWindow,
            maximumPacketSize: SSHServerChannel.maximumPacketSize,
            data: Uint8List(0),
          ).encode(),
        );
        unawaited(
          pumpForwardConnection(
            channel,
            result.connection,
            printDebug: _config.printDebug,
          ),
        );
    }
  }

  /// The `direct-tcpip` target predicate: the same per-connection
  /// [SSHForwardingConfig.permitOpen] verdict the forwarder uses, defaulting
  /// to allow when no predicate is configured (OpenSSH's `PermitOpen any`).
  Future<bool> _directTargetAllowed(String host, int port) async =>
      await _config.forwarding!.permitOpen?.call(this, host, port) ?? true;

  /// Refuses a channel open with a failure message. Replies are best-effort:
  /// when the transport is already gone (the connection is closing), the
  /// teardown owns the aftermath and the send is dropped silently.
  void _refuseChannelOpen(
    int recipientChannel,
    int reasonCode,
    String description,
  ) {
    try {
      _sendPacket(
        SSH_Message_Channel_Open_Failure(
          recipientChannel: recipientChannel,
          reasonCode: reasonCode,
          description: description,
        ).encode(),
      );
    } on Object {
      // transport is gone; the connection teardown owns the aftermath
    }
  }

  /// Routes a channel-scoped message to its channel by the recipient id the
  /// client addressed it to (our channel number). An unknown id is a
  /// protocol error, the way sshd treats a freed channel
  /// (channels.c:channel_from_packet_id,
  /// serverloop.c:server_input_channel_req) — except the two races where
  /// the id is legitimately gone or not yet resolved: a pending
  /// server-initiated open, and a channel this server closed whose CLOSE
  /// the client cannot have seen yet. See [_channelFromPacket].
  void _handleChannelMessage(Uint8List payload) {
    switch (SSHMessage.readMessageId(payload)) {
      case SSH_Message_Channel_Window_Adjust.messageId:
        final message = _decodeMessage(
          'window adjust',
          SSH_Message_Channel_Window_Adjust.decode,
          payload,
        );
        if (message == null) return;
        // sshd only logs an unknown-id adjust (channel_input_window_adjust)
        // — it never disconnects for this one.
        _channels[message.recipientChannel]
            ?.handleWindowAdjust(message.bytesToAdd);
        return;
      case SSH_Message_Channel_Data.messageId:
        final message = _decodeMessage(
          'channel data',
          SSH_Message_Channel_Data.decode,
          payload,
        );
        if (message == null) return;
        _channelFromPacket(
          message.recipientChannel,
          'data packet',
        )?.handleData(message.data);
        return;
      case SSH_Message_Channel_Extended_Data.messageId:
        final message = _decodeMessage(
          'extended channel data',
          SSH_Message_Channel_Extended_Data.decode,
          payload,
        );
        if (message == null) return;
        _channelFromPacket(
          message.recipientChannel,
          'extended data packet',
        )?.handleExtendedData(message.dataTypeCode, message.data);
        return;
      case SSH_Message_Channel_EOF.messageId:
        final message = _decodeMessage(
          'channel EOF',
          SSH_Message_Channel_EOF.decode,
          payload,
        );
        if (message == null) return;
        _channelFromPacket(
          message.recipientChannel,
          'ieof packet',
        )?.handleEof();
        return;
      case SSH_Message_Channel_Close.messageId:
        final message = _decodeMessage(
          'channel close',
          SSH_Message_Channel_Close.decode,
          payload,
        );
        if (message == null) return;
        final id = message.recipientChannel;
        // The client acknowledging our close completes the handshake: the
        // id moves from race-tolerated to fully reaped.
        if (_channels[id] == null && _closingChannels.remove(id)) {
          _reapedChannels.add(id);
          return;
        }
        _channelFromPacket(id, 'oclose packet')?.handleClose();
        return;
      case SSH_Message_Channel_Request.messageId:
        final message = _decodeMessage(
          'channel request',
          SSH_Message_Channel_Request.decode,
          payload,
        );
        if (message == null) return;
        _channelFromPacket(
          message.recipientChannel,
          // sshd's serverloop.c wording for requests, not the
          // channel_from_packet_id shape.
          'server_input_channel_req: unknown channel',
          rawDescription: true,
        )?.handleRequest(message);
        return;
    }
  }

  /// Resolves the channel a channel-scoped message addressed, applying the
  /// nonexistent-channel policy (F5, audit A15 + D05).
  ///
  /// - a live channel → that channel;
  /// - a pending server-initiated open → `null`, tolerated: the reply races
  ///   the open, and sshd's channel table still holds the OPENING channel;
  /// - a channel this server finished but the client has not closed yet →
  ///   `null`, tolerated: the message raced our CHANNEL_CLOSE (D05's race);
  /// - anything else → `DISCONNECT(2, "<what> referred to nonexistent
  ///   channel <id>")` and `null`.
  SSHServerChannel? _channelFromPacket(
    int id,
    String what, {
    bool rawDescription = false,
  }) {
    final channel = _channels[id];
    if (channel != null) return channel;
    if (_pendingOpens.containsKey(id) || _closingChannels.contains(id)) {
      return null;
    }
    _disconnect(
      SSHDisconnectReason.protocolError,
      rawDescription
          ? '$what $id'
          : '$what referred to nonexistent channel $id',
    );
    return null;
  }

  /// Records one channel finishing: its id leaves the live table, and —
  /// depending on whether the client's CHANNEL_CLOSE was already received —
  /// lands in the race-tolerated or the fully-reaped set (see
  /// [_closingChannels] and [_reapedChannels]).
  void _onChannelClosed(SSHServerChannel channel) {
    _channels.remove(channel.ourChannel);
    if (channel.receivedClose) {
      _reapedChannels.add(channel.ourChannel);
    } else {
      _closingChannels.add(channel.ourChannel);
    }
  }

  /// Takes a channel down together with the whole connection: the channel
  /// reported a violation the protocol makes fatal for the connection (the
  /// receive window being overrun past its grace margin), so the peer is
  /// answered with a `DISCONNECT(2, description)` before the teardown.
  void _disconnectForChannelViolation(String description) {
    _disconnect(SSHDisconnectReason.protocolError, description);
  }

  /// Serves the client's verdict on a server-initiated channel open
  /// (RFC 4254 §5.1): a CHANNEL_OPEN_CONFIRMATION promotes the pending open
  /// to a live channel; a CHANNEL_OPEN_FAILURE resolves it to `null`. A
  /// verdict for an id that was never a pending open is a protocol error
  /// like any other channel-scoped message for a nonexistent channel —
  /// unless it races a channel the verdict already created (duplicate
  /// replies) or one that has since finished.
  void _handleChannelOpenReply(Uint8List payload) {
    switch (SSHMessage.readMessageId(payload)) {
      case SSH_Message_Channel_Confirmation.messageId:
        final message = _decodeMessage(
          'channel confirmation',
          SSH_Message_Channel_Confirmation.decode,
          payload,
        );
        if (message == null) return;
        final pending = _pendingOpens.remove(message.recipientChannel);
        if (pending == null) {
          _tolerateOrDisconnectOpenReply(
            message.recipientChannel,
            'open confirmation packet',
          );
          return;
        }
        // Register the channel synchronously before completing the open:
        // CHANNEL_DATA may follow the confirmation in the same transport
        // input, and the channel's single-subscription input buffers until
        // its pump subscribes (mirroring the fork's own client-side accept
        // path).
        final channel = SSHServerChannel(
          recipientChannel: message.senderChannel,
          ourChannel: message.recipientChannel,
          channelType: pending.channelType,
          peerInitialWindowSize: message.initialWindowSize,
          peerMaximumPacketSize: message.maximumPacketSize,
          sendPacket: _sendPacket,
          onClosed: _onChannelClosed,
          onProtocolViolation: _disconnectForChannelViolation,
          printDebug: _config.printDebug,
        );
        _channels[channel.ourChannel] = channel;
        pending.completer.complete(channel);
        return;
      case SSH_Message_Channel_Open_Failure.messageId:
        final message = _decodeMessage(
          'channel open failure',
          SSH_Message_Channel_Open_Failure.decode,
          payload,
        );
        if (message == null) return;
        final pending = _pendingOpens.remove(message.recipientChannel);
        if (pending == null) {
          _tolerateOrDisconnectOpenReply(
            message.recipientChannel,
            'open failure packet',
          );
          return;
        }
        pending.completer.complete(null);
        return;
    }
  }

  /// The unknown-id policy for an open verdict: tolerated when the channel
  /// is known in any form — live (a duplicate verdict for a channel the
  /// first verdict already created, the shape OpenSSH's
  /// `channel_input_open_confirmation` answers with a debug log and a
  /// return), or remembered as closing/reaped (a verdict racing the
  /// channel's finish) — a protocol error otherwise.
  void _tolerateOrDisconnectOpenReply(int id, String what) {
    if (_channels.containsKey(id)) {
      _config.printDebug?.call(
        'tp_sshd: ignoring $what for channel $id '
        '(duplicate verdict for a live channel)',
      );
      return;
    }
    if (_closingChannels.contains(id) || _reapedChannels.contains(id)) return;
    _disconnect(
      SSHDisconnectReason.protocolError,
      '$what referred to nonexistent channel $id',
    );
  }

  /// Opens a server-initiated channel (RFC 4254 §5.1, the direction the
  /// client-opened path does not cover): builds the open message through
  /// [buildOpen] with the channel number this server allocates, sends it,
  /// and completes with the live channel once the client confirms — or
  /// `null` when the client refuses, or the connection ends before the
  /// verdict arrives.
  Future<SSHServerChannel?> _openServerChannel(
    SSH_Message_Channel_Open Function(int senderChannel) buildOpen,
  ) {
    if (_phase == _Phase.closed) return Future.value(null);
    // The same per-connection cap bounds the server-initiated direction (the
    // forwarder's `forwarded-tcpip` opens): at the cap the open is not even
    // attempted, so the channel table cannot be blown through the back door.
    if (_channels.length + _pendingOpens.length >= _config.maxChannels) {
      return Future.value(null);
    }
    final ourChannel = _nextChannelNumber++;
    final open = buildOpen(ourChannel);
    final pending = _PendingOpen(open.channelType);
    _pendingOpens[ourChannel] = pending;
    _sendPacket(open.encode());
    return pending.completer.future;
  }

  /// Opens the `forwarded-tcpip` channel for one accepted forwarded
  /// connection (RFC 4254 §7.2). The connected address is the host string
  /// the client asked to forward — clients match remote forwards by that
  /// string — with the port actually bound; the originator is the
  /// connecting peer.
  Future<SSHServerChannel?> _openForwardedChannel({
    required String connectedAddress,
    required int connectedPort,
    required String originatorAddress,
    required int originatorPort,
  }) {
    return _openServerChannel(
      (senderChannel) => SSH_Message_Channel_Open.forwardedTcpip(
        senderChannel: senderChannel,
        initialWindowSize: SSHServerChannel.initialReceiveWindow,
        maximumPacketSize: SSHServerChannel.maximumPacketSize,
        host: connectedAddress,
        port: connectedPort,
        originatorIP: originatorAddress,
        originatorPort: originatorPort,
      ),
    );
  }

  /// Decodes [payload] with [decode], disconnecting the peer with a
  /// protocol error instead of answering when it is malformed. Returns
  /// `null` in that case (and after the disconnect, nowhere else).
  T? _decodeMessage<T>(
    String what,
    T Function(Uint8List payload) decode,
    Uint8List payload,
  ) {
    try {
      return decode(payload);
    } on Object {
      _disconnect(SSHDisconnectReason.protocolError, 'Malformed $what');
      return null;
    }
  }

  /// Detaches every open channel without sending anything: the transport is
  /// going away. Pending server-initiated opens can never be confirmed
  /// after that either, so they resolve to `null` — their waiters (the
  /// forwarder's accepted connections) let go instead of hanging.
  void _teardownChannels() {
    for (final channel in List.of(_channels.values)) {
      channel.detach();
    }
    _channels.clear();
    _closingChannels.clear();
    _reapedChannels.clear();
    for (final pending in _pendingOpens.values) {
      pending.completer.complete(null);
    }
    _pendingOpens.clear();
  }

  /// Handles one `SSH_Message_Userauth_Request` (RFC 4252).
  ///
  /// Publickey is the only method served, and only for
  /// [SSHServerConfig.expectedUsername]. Probing requests (no signature) are
  /// answered with `USERAUTH_PK_Ok` when [SSHServerConfig.authenticate]
  /// trusts the key; signed requests authenticate only when the RFC 4252 §7
  /// signature verifies AND the key is trusted. Every failure counts toward
  /// [SSHServerConfig.maxAuthAttempts].
  Future<void> _handleUserauthRequest(Uint8List payload) async {
    // The anti-oracle floor is measured from the request's receipt, so the
    // clock starts here, before any failure path is taken.
    final receivedAt = DateTime.now();
    final SSH_Message_Userauth_Request message;
    try {
      message = SSH_Message_Userauth_Request.decode(payload);
    } on Object {
      _disconnect(
        SSHDisconnectReason.protocolError,
        'Malformed userauth request',
      );
      return;
    }

    if (message.methodName != 'publickey' ||
        message.user != _config.expectedUsername) {
      // Fail closed: no other method is served, and requests for any other
      // user are failed (counted), not answered.
      _failAuthAttempt(receivedAt);
      return;
    }

    final publicKeyAlgorithm = message.publicKeyAlgorithm;
    final publicKey = message.publicKey;
    if (publicKeyAlgorithm == null || publicKey == null) {
      _failAuthAttempt(receivedAt);
      return;
    }

    if (message.signature != null) {
      // A signed request must prove possession of the private key before
      // the embedder is asked whether it trusts the public one.
      if (!verifyEd25519UserauthSignature(
        sessionId: _transport.sessionId!,
        request: message,
      )) {
        _failAuthAttempt(receivedAt);
        return;
      }
    }

    var trusted = false;
    try {
      trusted = await _config.authenticate(
        SSHServerAuthRequest(
          username: message.user,
          algorithm: publicKeyAlgorithm,
          publicKey: publicKey,
        ),
      );
    } on Object {
      // A misbehaving authenticate callback is a failed attempt, not an
      // unhandled error on the connection.
      trusted = false;
    }
    // The connection may have been closed (or torn down by the throttle)
    // while the embedder was deciding.
    if (_phase != _Phase.auth) return;

    if (message.signature == null) {
      // Public-key probing (RFC 4252 §7.8): tell the client the key is worth
      // signing with.
      if (trusted) {
        _sendPacket(
          SSH_Message_Userauth_PK_Ok(
            publicKeyAlgorithm: publicKeyAlgorithm,
            publicKey: publicKey,
          ).encode(),
        );
      } else {
        _failAuthAttempt(receivedAt);
      }
      return;
    }

    if (trusted) {
      // Authenticated: cancel the auth timeout so it cannot tear down a
      // live connection later, then start serving session traffic.
      _authTimer.cancel();
      _phase = _Phase.running;
      _armRekeyTimer();
      _sendPacket(SSH_Message_Userauth_Success().encode());
      // The success twin of [_failAuthAttempt]: the embedder now knows this
      // connection belongs to whoever authenticated with this key.
      _config.onAuthenticated?.call(
        this,
        SSHServerAuthRequest(
          username: message.user,
          algorithm: publicKeyAlgorithm,
          publicKey: publicKey,
        ),
      );
      return;
    }
    _failAuthAttempt(receivedAt);
  }

  /// Counts and answers one failed authentication attempt.
  ///
  /// The reply is padded out to [SSHServerConfig.authFailureMinDelay],
  /// measured from [receivedAt] — the moment the request was received — so
  /// that timing the reply cannot reveal which failure path was taken
  /// (wrong key vs unknown user vs malformed blob; sshd's
  /// `ensure_minimum_time_since`).
  ///
  /// After [SSHServerConfig.maxAuthAttempts] failures the connection is
  /// disconnected (RFC 4253 §11.1 reason 14) instead of answered. The
  /// failure advertises the continuable methods (`publickey`, RFC 4252 §8):
  /// clients like OpenSSH consult that list to decide whether to offer a
  /// publickey at all, and an empty list reads as "no methods available" —
  /// ending a login that would have succeeded (audit A09/A10/A11).
  Future<void> _failAuthAttempt(DateTime receivedAt) async {
    _authAttempts += 1;
    // The throttle verdict is taken at receipt, in dispatch order, BEFORE
    // the padding below: pipelined requests all increment the counter long
    // before their padded replies go out, so re-reading it after the pad
    // would let an early reply answer for a later attempt (the first reply
    // would disconnect instead of the maxAuthAttempts-th).
    final throttled = _authAttempts >= _config.maxAuthAttempts;
    final minDelay = _config.authFailureMinDelay;
    if (minDelay > Duration.zero) {
      final remaining = minDelay - DateTime.now().difference(receivedAt);
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
    }
    // The connection may have been closed while the failure reply was being
    // padded out.
    if (_phase != _Phase.auth) return;
    if (throttled) {
      _disconnect(
        SSHDisconnectReason.noMoreAuthMethodsAvailable,
        'Too many failed authentication attempts',
      );
      return;
    }
    _sendPacket(
      SSH_Message_Userauth_Failure(methodsLeft: const ['publickey']).encode(),
    );
  }

  /// Closes connections that never finished authenticating.
  void _onAuthTimeout() {
    if (_phase != _Phase.auth) return;
    _config.printDebug?.call(
      'tp_sshd: closing connection after auth timeout '
      '(${_config.authTimeout})',
    );
    unawaited(close());
  }

  void _onTransportClosed() {
    _authTimer.cancel();
    _rekeyTimer?.cancel();
    _phase = _Phase.closed;
    _teardownChannels();
    // Release the binds too; the transport is already gone, so nothing can
    // be replied to anymore and the release runs unwatched.
    unawaited(_forwarder?.close());
  }

  /// Sends a disconnect message and closes the connection.
  void _disconnect(SSHDisconnectReason reason, String description) {
    _sendPacket(
      SSH_Message_Disconnect(
        reasonCode: reason.code,
        description: description,
      ).encode(),
    );
    unawaited(close());
  }
}

/// A server-initiated channel open awaiting the client's verdict.
class _PendingOpen {
  _PendingOpen(this.channelType);

  /// The channel type that was opened; the confirmation does not carry it
  /// back, so the pending open has to remember it.
  final String channelType;

  /// Completes with the live channel on confirmation, or `null` when the
  /// open is refused or the connection ends first.
  final completer = Completer<SSHServerChannel?>();
}
