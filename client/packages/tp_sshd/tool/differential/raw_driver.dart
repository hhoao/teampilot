/// Raw differential driver: dials one audit server over real TCP and
/// records what it sends back, either through a dartssh2 [SSHTransport]
/// (the in-memory pattern `test/dual_test_utils.dart` proves, moved onto
/// `Socket.connect`) or fully raw when a custom version string must go out
/// before the protocol proper (transport-level corruption rows).
///
/// VM-only tool code: `dart:io` sockets.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart'
    show SSHDisconnectError, SSHKeyPair, SSHSocket, SSHTransport;
import 'package:dartssh2/protocol.dart'
    show
        SSHMessage,
        SSH_Message_Channel_Open_Failure,
        SSH_Message_Userauth_Failure,
        SSH_Message_Userauth_Request,
        SSH_Message_Service_Request;

/// One thing the dialed server did that an audit row records.
///
/// A sealed hierarchy rather than a record: Dart has no sealed records, and
/// exhaustive `switch` over the variants is how audit rows compare servers.
sealed class Observed {
  const Observed();
}

/// One SSH message the server sent, by numeric id and its common name.
class MessageObservation extends Observed {
  const MessageObservation(this.id, this.name, [this.detail]);

  final int id;
  final String name;

  /// Payload-derived detail for the messages whose content is itself an
  /// audit observable (`USERAUTH_FAILURE`'s methods list,
  /// `CHANNEL_OPEN_FAILURE`'s reason code and description); `null` when the
  /// id alone says everything.
  final String? detail;

  @override
  String toString() =>
      detail == null ? 'msg:$id($name)' : 'msg:$id($name, $detail)';
}

/// An `SSH_MSG_DISCONNECT` the server sent.
class DisconnectObservation extends Observed {
  const DisconnectObservation(this.reasonCode, this.description);

  final int reasonCode;
  final String description;

  @override
  String toString() => 'disconnect:$reasonCode("$description")';
}

/// The TCP connection closed (with or without an error on the wire).
class ClosedObservation extends Observed {
  const ClosedObservation();

  @override
  String toString() => 'closed';
}

/// Common names for the SSH message ids the dartssh2/tp_sshd message
/// classes define (RFC 4253 §11.1 numbering). Ids 30/31/60 are shared by
/// message families that never co-occur on one connection (DH and ECDH key
/// exchange, password-change and userauth-info); the name recorded is the
/// family's first member.
const sshMessageNames = <int, String>{
  1: 'DISCONNECT',
  2: 'IGNORE',
  3: 'UNIMPLEMENTED',
  4: 'DEBUG',
  5: 'SERVICE_REQUEST',
  6: 'SERVICE_ACCEPT',
  7: 'EXT_INFO',
  20: 'KEXINIT',
  21: 'NEWKEYS',
  30: 'KEXDH_INIT',
  31: 'KEXDH_REPLY',
  32: 'DH_GEX_INIT',
  33: 'DH_GEX_REPLY',
  34: 'DH_GEX_REQUEST',
  50: 'USERAUTH_REQUEST',
  51: 'USERAUTH_FAILURE',
  52: 'USERAUTH_SUCCESS',
  53: 'USERAUTH_BANNER',
  60: 'USERAUTH_INFO_REQUEST',
  61: 'USERAUTH_INFO_RESPONSE',
  80: 'GLOBAL_REQUEST',
  81: 'REQUEST_SUCCESS',
  82: 'REQUEST_FAILURE',
  90: 'CHANNEL_OPEN',
  91: 'CHANNEL_OPEN_CONFIRMATION',
  92: 'CHANNEL_OPEN_FAILURE',
  93: 'CHANNEL_WINDOW_ADJUST',
  94: 'CHANNEL_DATA',
  95: 'CHANNEL_EXTENDED_DATA',
  96: 'CHANNEL_EOF',
  97: 'CHANNEL_CLOSE',
  98: 'CHANNEL_REQUEST',
  99: 'CHANNEL_SUCCESS',
  100: 'CHANNEL_FAILURE',
};

/// The common name for [id], or `UNKNOWN_<id>` for ids outside the table.
String sshMessageName(int id) => sshMessageNames[id] ?? 'UNKNOWN_$id';

/// dartssh2 message classes the [SSHTransport] handles internally, so they
/// never reach `onMessage`. The raw driver recovers their ids from the
/// transport's trace log instead (`'<- …: Instance of …'` and
/// `'<- …: SSH_Message_NewKeys'`), keyed by class name.
const _tracedMessageIds = <String, int>{
  'SSH_Message_Disconnect': 1,
  'SSH_Message_Ignore': 2,
  'SSH_Message_Unimplemented': 3,
  'SSH_Message_Debug': 4,
  'SSH_Message_ExtInfo': 7,
  'SSH_Message_KexInit': 20,
  'SSH_Message_NewKeys': 21,
  'SSH_Message_KexDH_Init': 30,
  'SSH_Message_KexECDH_Init': 30,
  'SSH_Message_KexDH_Reply': 31,
  'SSH_Message_KexECDH_Reply': 31,
  'SSH_Message_KexDH_GexGroup': 31,
  'SSH_Message_KexDH_GexInit': 32,
  'SSH_Message_KexDH_GexReply': 33,
  'SSH_Message_KexDH_GexRequest': 34,
};

final _tracedMessageToken = RegExp(r'SSH_Message_[A-Za-z0-9_]+');

/// A dialed, recording connection to one audit server.
class RawSession {
  RawSession._(this._socket, this.transport) {
    final transport = this.transport;
    if (transport != null) {
      // The transport handles DISCONNECT internally (closeWithError), so the
      // observation comes from its done future, not onMessage.
      transport.done.then(
        (_) => _recordEnd(null),
        onError: (Object error, _) => _recordEnd(error),
      );
    } else {
      _rawSubscription = _socket.listen(
        rawInbound.add,
        onError: (Object _) => _recordEnd(null),
        onDone: () => _recordEnd(null),
      );
    }
    // Neither lifecycle future is awaited by every dial mode (raw sessions
    // never reach KEX), but both complete with an error when the connection
    // ends. Default handlers keep those completions from surfacing as
    // unhandled async errors; row code that awaits still gets the result.
    _keyExchangeCompleter.future.ignore();
    _authenticatedCompleter.future.ignore();
  }

  final Socket _socket;
  StreamSubscription<Uint8List>? _rawSubscription;

  /// The client-side transport driving the protocol, when this session was
  /// dialed without a custom version string. `null` in raw mode, where the
  /// caller owns every byte on the wire.
  final SSHTransport? transport;

  /// Bytes the server sent before the SSH protocol proper (raw mode only):
  /// version-exchange replies such as OpenSSH's `Protocol mismatch`.
  final List<Uint8List> rawInbound = [];

  final List<Observed> _observations = [];
  final Completer<DisconnectObservation?> _disconnectCompleter =
      Completer<DisconnectObservation?>();
  final Completer<void> _keyExchangeCompleter = Completer<void>();
  final Completer<void> _authenticatedCompleter = Completer<void>();
  var _ended = false;

  /// The initial key exchange, complete (post-NEWKEYS). Rows injecting
  /// post-KEX traffic await this first. Completes with an error when the
  /// connection ends before the exchange completes.
  Future<void> get keyExchangeDone => _keyExchangeCompleter.future;

  /// `SSH_MSG_USERAUTH_SUCCESS` observed — the publickey login went through.
  /// Completes with an error when the connection ends first.
  Future<void> get authenticated => _authenticatedCompleter.future;

  /// Writes [bytes] straight onto the TCP socket, bypassing [transport].
  ///
  /// For pre-KEX corruption rows (bad version strings, garbage bytes) and
  /// for injecting extra bytes on the wire under an established transport.
  Future<void> sendRawBytes(Uint8List bytes) async {
    _socket.add(bytes);
    await _socket.flush();
  }

  /// Waits [window] for observations to accumulate, then snapshots them.
  Future<List<Observed>> collect({
    Duration window = const Duration(seconds: 2),
  }) async {
    await Future<void>.delayed(window);
    return List<Observed>.unmodifiable(_observations);
  }

  /// Completes with the DISCONNECT the server sent, or `null` when the
  /// connection ends without one.
  Future<DisconnectObservation?> get disconnectObserved =>
      _disconnectCompleter.future;

  /// Tears the connection down. Idempotent.
  Future<void> close() async {
    await _rawSubscription?.cancel();
    await transport?.close();
    _socket.destroy();
    _recordEnd(null);
  }

  void _recordEnd(Object? error) {
    if (_ended) return;
    _ended = true;
    if (error is SSHDisconnectError) {
      final observation = DisconnectObservation(
        error.reasonCode,
        error.message,
      );
      _observations.add(observation);
      _disconnectCompleter.complete(observation);
    } else {
      _observations.add(const ClosedObservation());
      _disconnectCompleter.complete(null);
    }
    final closed = StateError('connection ended');
    if (!_keyExchangeCompleter.isCompleted) {
      _keyExchangeCompleter.completeError(closed);
    }
    if (!_authenticatedCompleter.isCompleted) {
      _authenticatedCompleter.completeError(closed);
    }
  }

  void _recordMessage(Uint8List payload) {
    final id = SSHMessage.readMessageId(payload);
    _observations.add(MessageObservation(id, sshMessageName(id), _detailOf(id, payload)));
    if (id == 52 && !_authenticatedCompleter.isCompleted) {
      _authenticatedCompleter.complete();
    }
  }

  /// The payload detail recorded for the messages whose content is itself
  /// an audit observable. Decoding is best-effort: a decode failure must not
  /// mask the id-level observation.
  String? _detailOf(int id, Uint8List payload) {
    try {
      switch (id) {
        case SSH_Message_Userauth_Failure.messageId:
          final failure = SSH_Message_Userauth_Failure.decode(payload);
          return 'methods=[${failure.methodsLeft.join(',')}]';
        case SSH_Message_Channel_Open_Failure.messageId:
          final failure = SSH_Message_Channel_Open_Failure.decode(payload);
          return 'reason=${failure.reasonCode} "${failure.description}"';
      }
    } on Object {
      return null;
    }
    return null;
  }

  /// Records a transport-layer message the transport handled internally
  /// (DISCONNECT, IGNORE, UNIMPLEMENTED, DEBUG, EXT_INFO, the KEX family),
  /// which `onMessage` never sees. The trace line is the only place its
  /// decoded form surfaces.
  void _recordTracedMessage(String line) {
    final token = _tracedMessageToken.firstMatch(line)?.group(0);
    if (token == null) return;
    final id = _tracedMessageIds[token];
    if (id == null) return;
    _observations.add(MessageObservation(id, sshMessageName(id)));
  }

  void _completeKeyExchange() {
    if (!_keyExchangeCompleter.isCompleted) {
      _keyExchangeCompleter.complete();
    }
  }
}

/// Dials [port] on loopback as a raw SSH client.
///
/// Without [versionString], a dartssh2 [SSHTransport] drives the handshake
/// (ident `SSH-2.0-DartSSH_2.0`, host keys accepted) and every incoming
/// message is recorded via `onMessage`.
///
/// With [versionString], no transport is created: the string is written
/// verbatim (plus CRLF) as the identification line, the caller drives any
/// further bytes with [RawSession.sendRawBytes], and [RawSession.rawInbound]
/// captures whatever the server answers before the protocol proper.
Future<RawSession> dialRaw({required int port, String? versionString}) async {
  final socket = await Socket.connect('127.0.0.1', port);
  if (versionString != null) {
    final session = RawSession._(socket, null);
    await session.sendRawBytes(
      Uint8List.fromList('$versionString\r\n'.codeUnits),
    );
    return session;
  }
  return _dialTransport(socket);
}

/// Dials [port] and drives the client-side key exchange to completion, then
/// stops: the connection is post-NEWKEYS but pre-authentication. Audit rows
/// take it from there through [RawSession.transport]'s `sendPacket`.
Future<RawSession> dialPostKex({required int port}) async {
  final socket = await Socket.connect('127.0.0.1', port);
  return _dialTransport(socket);
}

/// Dials [port], completes the key exchange, negotiates `ssh-userauth`, and
/// authenticates with [identity] (ed25519 publickey, RFC 4252 §7 signature
/// over the transport-composed challenge). Completes when
/// [RawSession.authenticated] fires — the returned session is post-auth.
///
/// [signChallenge] overrides the signature: the challenge bytes are handed
/// to it instead of the identity, for rows that need an invalid signature.
Future<RawSession> dialAuthenticated({
  required int port,
  required SSHKeyPair identity,
  required String username,
  Uint8List Function(Uint8List challenge)? signChallenge,
}) async {
  final socket = await Socket.connect('127.0.0.1', port);
  final publicKey = identity.toPublicKey().encode();
  return _dialTransport(socket, onReady: (transport) {
    transport.sendPacket(
      SSH_Message_Service_Request('ssh-userauth').encode(),
    );
    // The RFC 4252 §7 signed request: the challenge is the session-id
    // prefixed request-without-signature (same construction as
    // test/dual_test_utils.dart).
    final challenge = transport.composeChallenge(
      username: username,
      service: 'ssh-connection',
      publicKeyAlgorithm: 'ssh-ed25519',
      publicKey: publicKey,
    );
    final signature = signChallenge != null
        ? signChallenge(challenge)
        : identity.sign(challenge).encode();
    transport.sendPacket(
      SSH_Message_Userauth_Request.publicKey(
        username: username,
        publicKeyAlgorithm: 'ssh-ed25519',
        publicKey: publicKey,
        signature: signature,
      ).encode(),
    );
  });
}

/// The transport-mode dial shared by [dialRaw] (no version override),
/// [dialPostKex] and [dialAuthenticated].
///
/// The transport starts the handshake in its constructor and traces its
/// outgoing lines synchronously there, before the session below exists —
/// hence the nullable holder. Incoming lines only arrive on a later
/// event-loop turn, by which time the holder is set.
RawSession _dialTransport(
  Socket socket, {
  void Function(SSHTransport transport)? onReady,
}) {
  RawSession? session;
  late final SSHTransport transport;
  transport = SSHTransport(
    _ClientSocket(socket),
    onVerifyHostKey: (_, __) => true,
    printTrace: (line) {
      // Only incoming lines carry the peer's messages; outgoing ones are
      // the driver's own traffic.
      if (line != null && line.startsWith('<- ')) {
        session?._recordTracedMessage(line);
      }
    },
    onMessage: (payload) {
      // Recording is a pure side effect; every message counts as handled so
      // the transport never answers on the driver's behalf.
      session?._recordMessage(payload);
      return true;
    },
    onReady: () {
      session?._completeKeyExchange();
      onReady?.call(transport);
    },
  );
  final rawSession = RawSession._(socket, transport);
  session = rawSession;
  return rawSession;
}

/// A dart:io [Socket] exposed as the [SSHTransport]'s [SSHSocket].
class _ClientSocket implements SSHSocket {
  _ClientSocket(this._socket);

  final Socket _socket;

  @override
  Stream<Uint8List> get stream => _socket;

  @override
  StreamSink<List<int>> get sink => _socket;

  @override
  Future<void> get done => _socket.done;

  @override
  Future<void> close() => _socket.close();

  @override
  void destroy() => _socket.destroy();

  @override
  Future<void> flush() => _socket.flush();
}
