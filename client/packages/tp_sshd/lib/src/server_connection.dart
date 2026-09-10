import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' show SSHSocket, SSHTransport;
import 'package:dartssh2/protocol.dart';

import 'server_channel.dart';
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
    final bindServerSocket = config.bindServerSocket;
    if (bindServerSocket != null) {
      _forwarder = SSHServerForwarder(
        bindServerSocket: bindServerSocket,
        openForwardedChannel: _openForwardedChannel,
        sendPacket: _transport.sendPacket,
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

  /// Server-initiated channel opens awaiting the client's verdict, keyed by
  /// the channel number the open was sent with (see [_openServerChannel]).
  final _pendingOpens = <int, _PendingOpen>{};

  /// The next channel number to assign. A plain counter is enough: channel
  /// numbers are only reused after 2^32 opens.
  var _nextChannelNumber = 0;

  /// Failed authentication attempts so far, for the
  /// [SSHServerConfig.maxAuthAttempts] throttle.
  var _authAttempts = 0;

  /// Completes when the underlying transport closes, normally or with an
  /// error.
  Future<void> get done => _transport.done;

  /// The channels currently open on this connection, keyed by the
  /// server-assigned channel number.
  Map<int, SSHServerChannel> get channels => Map.unmodifiable(_channels);

  /// Closes the connection and its socket.
  Future<void> close() async {
    _authTimer.cancel();
    _phase = _Phase.closed;
    _teardownChannels();
    await _forwarder?.close();
    await _transport.close();
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
          _transport.sendPacket(
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
  /// Everything else — including forwarding when no bind seam is configured —
  /// is refused.
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
      // No seam configured: fall through to the refusal below.
      case 'keepalive@openssh.com':
        if (message.wantReply) {
          _transport.sendPacket(
            SSH_Message_Request_Success(Uint8List(0)).encode(),
          );
        }
        return;
    }
    if (message.wantReply) {
      _transport.sendPacket(SSH_Message_Request_Failure().encode());
    }
  }

  /// Serves CHANNEL_OPEN (RFC 4254 §5.1): `session` channels are confirmed
  /// with a fresh [SSHServerChannel]; every other type is refused with
  /// "administratively prohibited" (server-initiated opens — the outbound
  /// direction, used for `forwarded-tcpip` — go through
  /// [_openServerChannel] instead).
  ///
  /// The refusal uses reason 1, `codeAdministrativelyProhibited`. The plan
  /// text says "reason 3 (admin prohibited)", but reason 3 is
  /// `codeUnknownChannelType` in both the fork's API and RFC 4254 §5.1,
  /// and it would be the wrong semantic here (the server recognizes
  /// `direct-tcpip`, it just does not serve it); the named constant for
  /// the stated semantic wins per the controller ruling that real fork API
  /// names take precedence.
  void _handleChannelOpen(Uint8List payload) {
    final message = _decodeMessage(
      'channel open',
      SSH_Message_Channel_Open.decode,
      payload,
    );
    if (message == null) return;

    if (message.channelType != 'session') {
      _transport.sendPacket(
        SSH_Message_Channel_Open_Failure(
          recipientChannel: message.senderChannel,
          reasonCode:
              SSH_Message_Channel_Open_Failure.codeAdministrativelyProhibited,
          description: "Channel type '${message.channelType}' is not supported",
        ).encode(),
      );
      return;
    }

    // The per-connection channel cap (OpenSSH's default is 10): without it,
    // one connection could pin unbounded channel state on the server. Excess
    // opens are refused with reason 4, resource shortage (RFC 4254 §5.1's
    // "channel resource shortage" case).
    if (_channels.length >= _config.maxChannels) {
      _transport.sendPacket(
        SSH_Message_Channel_Open_Failure(
          recipientChannel: message.senderChannel,
          reasonCode: SSH_Message_Channel_Open_Failure.codeResourceShortage,
          description: 'Too many open channels (${_channels.length}/'
              '${_config.maxChannels})',
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
      sendPacket: _transport.sendPacket,
      onClosed: (channel) => _channels.remove(channel.ourChannel),
      printDebug: _config.printDebug,
    );
    // Session requests (exec today; shell and pty in Task 7) are served by
    // the session layer. The handler refuses everything it does not serve.
    channel.onRequest = (channel, request) =>
        handleSessionRequest(channel, request, config: _config);
    _channels[ourChannel] = channel;
    _transport.sendPacket(
      SSH_Message_Channel_Confirmation(
        recipientChannel: message.senderChannel,
        senderChannel: ourChannel,
        initialWindowSize: SSHServerChannel.initialReceiveWindow,
        maximumPacketSize: SSHServerChannel.maximumPacketSize,
        data: Uint8List(0),
      ).encode(),
    );
  }

  /// Routes a channel-scoped message to its channel by the recipient id the
  /// client addressed it to (our channel number). An unknown id is ignored
  /// silently: it is indistinguishable from a message racing the close that
  /// removed the channel.
  void _handleChannelMessage(Uint8List payload) {
    switch (SSHMessage.readMessageId(payload)) {
      case SSH_Message_Channel_Window_Adjust.messageId:
        final message = _decodeMessage(
          'window adjust',
          SSH_Message_Channel_Window_Adjust.decode,
          payload,
        );
        if (message == null) return;
        _channelOrNull(message.recipientChannel)
            ?.handleWindowAdjust(message.bytesToAdd);
        return;
      case SSH_Message_Channel_Data.messageId:
        final message = _decodeMessage(
          'channel data',
          SSH_Message_Channel_Data.decode,
          payload,
        );
        if (message == null) return;
        _channelOrNull(message.recipientChannel)?.handleData(message.data);
        return;
      case SSH_Message_Channel_Extended_Data.messageId:
        final message = _decodeMessage(
          'extended channel data',
          SSH_Message_Channel_Extended_Data.decode,
          payload,
        );
        if (message == null) return;
        _channelOrNull(message.recipientChannel)
            ?.handleExtendedData(message.dataTypeCode, message.data);
        return;
      case SSH_Message_Channel_EOF.messageId:
        final message = _decodeMessage(
          'channel EOF',
          SSH_Message_Channel_EOF.decode,
          payload,
        );
        if (message == null) return;
        _channelOrNull(message.recipientChannel)?.handleEof();
        return;
      case SSH_Message_Channel_Close.messageId:
        final message = _decodeMessage(
          'channel close',
          SSH_Message_Channel_Close.decode,
          payload,
        );
        if (message == null) return;
        _channelOrNull(message.recipientChannel)?.handleClose();
        return;
      case SSH_Message_Channel_Request.messageId:
        final message = _decodeMessage(
          'channel request',
          SSH_Message_Channel_Request.decode,
          payload,
        );
        if (message == null) return;
        _channelOrNull(message.recipientChannel)?.handleRequest(message);
        return;
    }
  }

  SSHServerChannel? _channelOrNull(int ourChannel) => _channels[ourChannel];

  /// Serves the client's verdict on a server-initiated channel open
  /// (RFC 4254 §5.1): a CHANNEL_OPEN_CONFIRMATION promotes the pending open
  /// to a live channel; a CHANNEL_OPEN_FAILURE resolves it to `null`.
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
        if (pending == null) return;
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
          sendPacket: _transport.sendPacket,
          onClosed: (channel) => _channels.remove(channel.ourChannel),
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
        _pendingOpens
            .remove(message.recipientChannel)
            ?.completer
            .complete(null);
        return;
    }
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
    _transport.sendPacket(open.encode());
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
      _failAuthAttempt();
      return;
    }

    final publicKeyAlgorithm = message.publicKeyAlgorithm;
    final publicKey = message.publicKey;
    if (publicKeyAlgorithm == null || publicKey == null) {
      _failAuthAttempt();
      return;
    }

    if (message.signature != null) {
      // A signed request must prove possession of the private key before
      // the embedder is asked whether it trusts the public one.
      if (!verifyEd25519UserauthSignature(
        sessionId: _transport.sessionId!,
        request: message,
      )) {
        _failAuthAttempt();
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
        _transport.sendPacket(
          SSH_Message_Userauth_PK_Ok(
            publicKeyAlgorithm: publicKeyAlgorithm,
            publicKey: publicKey,
          ).encode(),
        );
      } else {
        _failAuthAttempt();
      }
      return;
    }

    if (trusted) {
      // Authenticated: cancel the auth timeout so it cannot tear down a
      // live connection later, then start serving session traffic.
      _authTimer.cancel();
      _phase = _Phase.running;
      _transport.sendPacket(SSH_Message_Userauth_Success().encode());
      return;
    }
    _failAuthAttempt();
  }

  /// Counts and answers one failed authentication attempt.
  ///
  /// After [SSHServerConfig.maxAuthAttempts] failures the connection is
  /// disconnected (RFC 4253 §11.1 reason 14) instead of answered. The
  /// failure never advertises continuable methods: publickey is the only
  /// method there is, and offering it would just invite another attempt.
  void _failAuthAttempt() {
    _authAttempts += 1;
    if (_authAttempts >= _config.maxAuthAttempts) {
      _disconnect(
        SSHDisconnectReason.noMoreAuthMethodsAvailable,
        'Too many failed authentication attempts',
      );
      return;
    }
    _transport.sendPacket(
      SSH_Message_Userauth_Failure(methodsLeft: const []).encode(),
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
    _phase = _Phase.closed;
    _teardownChannels();
    // Release the binds too; the transport is already gone, so nothing can
    // be replied to anymore and the release runs unwatched.
    unawaited(_forwarder?.close());
  }

  /// Sends a disconnect message and closes the connection.
  void _disconnect(SSHDisconnectReason reason, String description) {
    _transport.sendPacket(
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
