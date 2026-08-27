import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../utils/logging/logger_utils.dart';

/// One dial notification received over the register socket.
class ConnectRelayDialRequest {
  const ConnectRelayDialRequest({
    required this.channel,
    this.deviceId,
    this.inviteToken,
    this.relayGrant,
  });

  final String channel;
  final String? deviceId;
  final String? inviteToken;
  final String? relayGrant;
}

typedef ValidateRelayDial = Future<bool> Function(
  ConnectRelayDialRequest request,
);

/// Resolves the loopback target for a channel; null rejects the dial.
typedef ResolveRelayTarget =
    Future<({InternetAddress host, int port})?> Function(String channel);

typedef RelaySocketConnect = Future<WebSocket> Function(Uri url);

/// Desktop's outbound relay registration (`/register`).
///
/// The client never decides authorization: every dial is handed to
/// [validateDial] first, and a rejected (or unresolvable) dial simply never
/// opens a splice — the local pairing listener and sshd are untouched.
class ConnectRelayClient {
  ConnectRelayClient({
    required this.validateDial,
    required this.resolveTarget,
    RelaySocketConnect? connectSocket,
    this.retryDelay = const Duration(seconds: 5),
  }) : _connectSocket = connectSocket ?? _defaultConnect;

  static const _dialType = 'dial';
  static const _splicePath = '/splice';

  final ValidateRelayDial validateDial;
  final ResolveRelayTarget resolveTarget;
  final RelaySocketConnect _connectSocket;
  final Duration retryDelay;

  final Map<String, WebSocket> _splicesById = {};
  WebSocket? _socket;
  StreamSubscription<Object?>? _subscription;
  Timer? _reconnectTimer;
  Uri? _url;
  String? _hostId;
  var _started = false;

  bool get isConnected => _socket != null && _socket!.readyState == openState;

  Future<void> start({required Uri url, required String hostId}) async {
    _started = true;
    _url = url;
    _hostId = hostId;
    await _open();
  }

  Future<void> stop() async {
    _started = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    for (final splice in _splicesById.values) {
      await splice.close();
    }
    _splicesById.clear();
    await _socket?.close();
    _socket = null;
  }

  Future<void> _open() async {
    if (!_started || _url == null || _hostId == null) return;
    try {
      final socket = await _connectSocket(
        _url!.replace(
          path: '/register',
          queryParameters: {'hostId': _hostId},
        ),
      );
      _socket = socket;
      _subscription = socket.listen(
        (message) => unawaited(_onMessage(message)),
        onDone: () => _scheduleReconnect(),
        onError: (Object _) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.instance.w(
        '[connect-relay] register failed class=${error.runtimeType}',
        stackTrace: stackTrace,
      );
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _socket = null;
    if (!_started) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(retryDelay, () => unawaited(_open()));
  }

  Future<void> _onMessage(Object message) async {
    if (message is! String) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (decoded is! Map) return;
    if (decoded['type'] != _dialType) return;

    final channel = decoded['channel'];
    final spliceId = decoded['spliceId'];
    if (channel is! String || spliceId is! String) return;
    final request = ConnectRelayDialRequest(
      channel: channel,
      deviceId: decoded['deviceId'] as String?,
      inviteToken: decoded['inviteToken'] as String?,
      relayGrant: decoded['relayGrant'] as String?,
    );

    // Validate before anything local is touched. A rejection closes nothing
    // locally: no splice opens, so pairing HTTP and sshd stay unreachable.
    if (!await validateDial(request)) {
      AppLogger.instance.w(
        '[connect-relay] dial rejected channel=${request.channel}',
      );
      return;
    }
    final target = await resolveTarget(channel);
    if (target == null) {
      AppLogger.instance.w(
        '[connect-relay] dial rejected channel=$channel reason=noTarget',
      );
      return;
    }
    await _openSplice(spliceId: spliceId, target: target);
  }

  Future<void> _openSplice({
    required String spliceId,
    required ({InternetAddress host, int port}) target,
  }) async {
    if (_url == null) return;
    try {
      final splice = await _connectSocket(
        _url!.replace(path: _splicePath, queryParameters: {'id': spliceId}),
      );
      final existing = _splicesById.remove(spliceId);
      await existing?.close();
      _splicesById[spliceId] = splice;

      final socket = await Socket.connect(target.host, target.port);
      _pipe(splice, socket);
    } on Object catch (error, stackTrace) {
      AppLogger.instance.w(
        '[connect-relay] splice failed class=${error.runtimeType}',
        stackTrace: stackTrace,
      );
    }
  }

  void _pipe(WebSocket splice, Socket socket) {
    splice.listen(
      (data) => socket.add(data as List<int>),
      onDone: () {
        socket.destroy();
        _splicesById.removeWhere((_, value) => identical(value, splice));
      },
      onError: (Object _) {
        socket.destroy();
        _splicesById.removeWhere((_, value) => identical(value, splice));
      },
      cancelOnError: true,
    );
    socket.listen(
      splice.add,
      onDone: () => unawaited(splice.close()),
      onError: (Object _) => unawaited(splice.close()),
      cancelOnError: true,
    );
  }
}

const openState = WebSocket.open;

Future<WebSocket> _defaultConnect(Uri url) => WebSocket.connect(url.toString());
