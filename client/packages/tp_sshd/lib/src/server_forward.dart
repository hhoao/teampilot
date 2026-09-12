import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/protocol.dart'
    show
        SSHMessageWriter,
        SSH_Message_Global_Request,
        SSH_Message_Request_Failure,
        SSH_Message_Request_Success;

import 'server_channel.dart';

/// Injection seam for loopback binds: the app passes a `ServerSocket.bind`
/// adapter, tests pass fakes (or a recording wrapper) to observe or refuse
/// binds without sockets.
typedef SSHBindServerSocket = Future<ServerSocketHandle> Function(
    InternetAddress address, int port);

/// A bound loopback listener behind one accepted `tcpip-forward` request.
/// Implemented by the app over a real `ServerSocket`; faked in tests.
abstract class ServerSocketHandle {
  /// The port actually bound — the ephemeral result when 0 was requested.
  /// Carried back to the client in the Request_Success payload.
  int get port;

  /// Connections accepted on the bound port.
  Stream<ForwardConnection> get connections;

  /// Stops listening. Must be safe to call more than once.
  Future<void> close();
}

/// One accepted TCP connection behind a forwarded port: its bytes ride a
/// `forwarded-tcpip` channel. Implemented by the app over a real [Socket];
/// faked in tests.
abstract class ForwardConnection {
  /// Bytes the connected peer sends; must close when the peer disconnects.
  Stream<Uint8List> get input;

  /// Bytes to deliver to the connected peer.
  StreamSink<List<int>> get output;

  /// Completes when the connection is over — the peer went away or the
  /// socket was destroyed.
  Future<void> get done;

  /// The peer's address, reported as the `forwarded-tcpip` originator
  /// address (RFC 4254 §7.2). Informational: clients match remote forwards
  /// by the connected address and port, not the originator.
  InternetAddress get remoteAddress;

  /// The peer's TCP port; see [remoteAddress].
  int get remotePort;

  /// Tears the connection down in both directions, dropping anything not
  /// yet delivered. Must be safe to call more than once, and after [done].
  void destroy();
}

/// Opens the `forwarded-tcpip` channel for one accepted connection. Provided
/// by the connection — it owns the channel numbers, the channel table and
/// the wire. Completes with `null` when the client refuses the open or the
/// connection is gone before the verdict arrives.
typedef SSHForwardedChannelOpener = Future<SSHServerChannel?> Function({
  required String connectedAddress,
  required int connectedPort,
  required String originatorAddress,
  required int originatorPort,
});

/// Remote port forwarding for one SSH connection (RFC 4254 §7): serves
/// `tcpip-forward` / `cancel-tcpip-forward` global requests by binding
/// loopback ports through the injected [SSHBindServerSocket] seam, and pumps
/// every accepted connection over a server-initiated `forwarded-tcpip`
/// channel.
///
/// Only loopback is ever bound — `127.0.0.1`, `::1` and `localhost` — and a
/// non-loopback request is refused before the seam is ever consulted. A bind
/// requested with port 0 gets an ephemeral port; the Request_Success payload
/// carries the port actually bound. Cancelling releases the listener (live
/// pumped connections keep running until they — or the connection — end),
/// and the connection's teardown releases every bind it holds.
class SSHServerForwarder {
  SSHServerForwarder({
    required SSHBindServerSocket bindServerSocket,
    required SSHForwardedChannelOpener openForwardedChannel,
    required void Function(Uint8List payload) sendPacket,
    this.printDebug,
  })  : _bindServerSocket = bindServerSocket,
        _openForwardedChannel = openForwardedChannel,
        _sendPacket = sendPacket;

  final SSHBindServerSocket _bindServerSocket;
  final SSHForwardedChannelOpener _openForwardedChannel;
  final void Function(Uint8List payload) _sendPacket;

  /// Function invoked with debug logging, mirroring [SSHServerConfig].
  final void Function(String? message)? printDebug;

  /// The binds this connection owns, keyed by the bound address and the port
  /// actually bound (which is what a cancel echoes back).
  final _binds = <String, _ForwardBind>{};

  var _closed = false;

  /// Serves one forwarding global request. Replies itself — binding is
  /// asynchronous, so the reply cannot come from the caller's synchronous
  /// dispatch.
  Future<void> handleGlobalRequest(SSH_Message_Global_Request request) async {
    if (_closed) return;
    switch (request.requestName) {
      case 'tcpip-forward':
        await _handleTcpipForward(request);
      case 'cancel-tcpip-forward':
        await _handleCancelTcpipForward(request);
    }
  }

  /// Releases every bind this connection made. Live pumped connections are
  /// closed through their channels: connection teardown detaches the
  /// channels, and each pump destroys its TCP connection when that happens.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final binds = List.of(_binds.values);
    _binds.clear();
    for (final bind in binds) {
      await _releaseBind(bind);
    }
  }

  Future<void> _handleTcpipForward(SSH_Message_Global_Request request) async {
    final requestedHost = request.bindAddress;
    final requestedPort = request.bindPort;
    if (requestedHost == null || requestedPort == null) {
      _reply(request, success: false);
      return;
    }

    final bindAddress = _loopbackBindAddress(requestedHost);
    if (bindAddress == null) {
      printDebug?.call(
        'tp_sshd: refusing tcpip-forward for non-loopback address '
        "'$requestedHost'",
      );
      _reply(request, success: false);
      return;
    }

    final ServerSocketHandle handle;
    try {
      handle = await _bindServerSocket(bindAddress, requestedPort);
    } on Object {
      // A bind that fails — port in use, seam unavailable — is a refused
      // request, not a dead connection.
      _reply(request, success: false);
      return;
    }
    if (_closed) {
      // The connection went away while the bind settled.
      _discard(handle.close());
      return;
    }

    final bind = _ForwardBind(
      clientHost: requestedHost,
      address: bindAddress,
      port: handle.port,
      handle: handle,
    );
    // Register before replying, so a cancel that races the reply still finds
    // the bind.
    _binds[bind.key] = bind;
    bind.listen((connection) {
      unawaited(_serveAcceptedConnection(bind, connection));
    });
    _reply(request, success: true, boundPort: bind.port);
  }

  Future<void> _handleCancelTcpipForward(
    SSH_Message_Global_Request request,
  ) async {
    final host = request.bindAddress;
    final port = request.bindPort;
    final bindAddress =
        host == null || port == null ? null : _loopbackBindAddress(host);
    if (bindAddress == null) {
      // A cancel naming a non-loopback address names a bind this server
      // could never have made.
      _reply(request, success: false);
      return;
    }
    final bind = _binds.remove('${bindAddress.address}:$port');
    if (bind == null) {
      // A cancel naming a bind this connection does not hold — cancelled
      // already, never made, another connection's — is refused, so a client
      // can tell a released bind from a mistaken cancel.
      _reply(request, success: false);
      return;
    }
    await _releaseBind(bind);
    _reply(request, success: true);
  }

  /// Forwards one accepted connection over its own `forwarded-tcpip`
  /// channel (RFC 4254 §7.2) and pumps it until either side ends.
  Future<void> _serveAcceptedConnection(
    _ForwardBind bind,
    ForwardConnection connection,
  ) async {
    if (_closed) {
      connection.destroy();
      return;
    }
    final channel = await _openForwardedChannel(
      // The connected address is the host string exactly as the client
      // requested it: the fork's client matches remote forwards by that
      // string, not by the interface actually bound underneath.
      connectedAddress: bind.clientHost,
      connectedPort: bind.port,
      originatorAddress: connection.remoteAddress.address,
      originatorPort: connection.remotePort,
    );
    if (channel == null) {
      // The client refused the open, or the connection ended first.
      connection.destroy();
      return;
    }
    await _pump(channel, connection);
  }

  /// Pumps one accepted connection against its channel until either side
  /// ends: TCP bytes become channel data and back, the TCP side ending
  /// closes the channel, and the channel ending destroys the TCP side.
  Future<void> _pump(
    SSHServerChannel channel,
    ForwardConnection connection,
  ) {
    final subscriptions = <StreamSubscription<dynamic>>[];
    final finished = Completer<void>();
    var stopped = false;
    void stop() {
      if (stopped) return;
      stopped = true;
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
      if (!finished.isCompleted) finished.complete();
    }

    // TCP peer → client.
    subscriptions.add(
      connection.input.listen(
        channel.write,
        onError: (Object _) {},
        onDone: () {
          // The TCP side is over: no more bytes can arrive to forward, so
          // the channel finishes too.
          channel.close();
          stop();
        },
      ),
    );

    // Client → TCP peer.
    subscriptions.add(
      channel.input.listen(
        (data) {
          try {
            connection.output.add(data);
          } on Object {
            // The TCP side died mid-write; its own completion closes the
            // channel.
          }
        },
        onError: (Object _) {},
        onDone: () {
          // The client half-closed its channel: stop writing to the peer.
          connection.output.close().then((_) {}, onError: (Object _) {});
        },
      ),
    );

    // The channel ended — the client closed it, the channel protocol
    // failed, or the connection was torn down: the TCP connection has
    // nowhere left to go.
    channel.done.whenComplete(() {
      connection.destroy();
      stop();
    });

    // The TCP connection ended outright — failed, or destroyed from the
    // channel side above: finish the channel if it is not already finishing
    // itself.
    connection.done.whenComplete(() {
      channel.close();
      stop();
    });

    return finished.future;
  }

  /// Answers [request] with the global-request reply it asked for, carrying
  /// [boundPort] on success.
  void _reply(
    SSH_Message_Global_Request request, {
    required bool success,
    int? boundPort,
  }) {
    if (!request.wantReply) return;
    try {
      _sendPacket(
        success
            ? SSH_Message_Request_Success(
                _encodeUint32(boundPort ?? 0),
              ).encode()
            : SSH_Message_Request_Failure().encode(),
      );
    } on Object {
      // The transport went away while the request was being served; the
      // connection's teardown owns the rest.
    }
  }

  /// Stops serving [bind] and releases its listener.
  Future<void> _releaseBind(_ForwardBind bind) async {
    try {
      await bind.subscription?.cancel();
      await bind.handle.close();
    } on Object {
      printDebug?.call(
        'tp_sshd: releasing the forward bound to ${bind.address}:'
        '${bind.port} failed',
      );
    }
  }

  /// Runs [future], discarding its outcome: cleanup must never surface as
  /// an unhandled error on a connection that may already be gone.
  void _discard(Future<void> future) {
    future.then((_) {}, onError: (Object _) {});
  }

  static Uint8List _encodeUint32(int value) {
    final writer = SSHMessageWriter()..writeUint32(value);
    return writer.takeBytes();
  }

  /// Maps a bind address a client asked for to the loopback interface to
  /// bind, or `null` when it is not a loopback spelling. Only `127.0.0.1`,
  /// `::1` and `localhost` qualify — the empty string, the wildcard
  /// addresses and any other host are refused before the bind seam is ever
  /// consulted. `localhost` binds IPv4 loopback, like a single-stack
  /// resolver; DNS is never touched, so a name that happens to resolve to
  /// loopback is still refused.
  static InternetAddress? _loopbackBindAddress(String address) {
    switch (address) {
      case '127.0.0.1':
        return InternetAddress.loopbackIPv4;
      case '::1':
        return InternetAddress.loopbackIPv6;
      case 'localhost':
        return InternetAddress.loopbackIPv4;
      default:
        return null;
    }
  }
}

/// One live bind: the listener, the port it actually got, and the address
/// spellings the two protocol directions need.
class _ForwardBind {
  _ForwardBind({
    required this.clientHost,
    required this.address,
    required this.port,
    required this.handle,
  });

  /// The host exactly as the client requested it (`'127.0.0.1'`,
  /// `'localhost'`, …). The `forwarded-tcpip` opens carry it verbatim,
  /// because clients match remote forwards by the string they asked with.
  final String clientHost;

  /// The loopback interface bound.
  final InternetAddress address;

  /// The port actually bound.
  final int port;

  /// The listener itself, through the injected seam.
  final ServerSocketHandle handle;

  StreamSubscription<ForwardConnection>? subscription;

  /// The registry key this bind is filed under.
  String get key => '${address.address}:$port';

  /// Starts accepting: every accepted connection is served on its own
  /// forwarded-tcpip channel.
  void listen(void Function(ForwardConnection connection) serve) {
    subscription = handle.connections.listen(
      serve,
      onError: (Object _) {},
      // The listener is gone — cancelled here, or the seam closed it;
      // there is nothing left to serve.
      onDone: () {},
    );
  }
}
