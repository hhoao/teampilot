import 'dart:async';
import 'dart:io';

import '../../cubits/session_remote_activity_cubit.dart';
import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import '../session_protocol/session_authority.dart';
import '../session_protocol/session_channel.dart';
import '../session_protocol/session_client.dart';
import '../session_protocol/session_envelope.dart';
import '../session_protocol/session_models.dart';
import '../session_protocol/session_server.dart';

enum SessionProtocolRole { none, server, client }

final class SessionProtocolServerConfig {
  const SessionProtocolServerConfig({
    required this.fs,
    required this.advertisePath,
    this.pid,
  });

  final Filesystem fs;
  final String advertisePath;
  final int Function()? pid;
}

/// Owns the app's session-protocol role.
///
/// Server: bind loopback, advertise the port in the home plane, and serve one
/// [SessionServer] per accepted socket. Client: reconnect to the SSH-forwarded
/// byte stream and project snapshots/deltas into [remoteCubit].
final class SessionProtocolController {
  SessionProtocolController({
    required this.deviceId,
    required this.remoteCubit,
    this.authority,
    this.onContentInvalidated,
    this.onAttention,
    int Function()? pid,
  }) : _pid = pid ?? _currentPid;

  static const _tag = 'session-protocol';

  final String deviceId;
  final SessionAuthority? authority;
  final SessionRemoteActivityCubit remoteCubit;
  final void Function(SessionContentInvalidated invalidation)?
  onContentInvalidated;
  final void Function(SessionAttention attention)? onAttention;
  final int Function() _pid;

  SessionProtocolRole _role = SessionProtocolRole.none;
  ServerSocket? _socket;
  SessionProtocolServerConfig? _serverConfig;
  final Set<SessionServer> _servers = {};
  SessionClientConnection? _client;
  Future<void>? _acceptLoop;
  Timer? _advertisementTimer;

  SessionProtocolRole get role => _role;

  bool get isClient => _role == SessionProtocolRole.client;

  Future<SessionIntentResult> cancelTurn({
    required String sessionId,
    required String memberId,
  }) {
    final client = _client;
    if (client == null) {
      return Future.value(
        const SessionIntentResult(
          id: '',
          status: SessionIntentStatus.rejected,
          code: 'not_connected',
        ),
      );
    }
    return client.cancelTurn(sessionId: sessionId, memberId: memberId);
  }

  static int _currentPid() => pid;

  Future<void> applyServer(SessionProtocolServerConfig config) async {
    await applyNone();
    final server = authority;
    if (server == null) {
      throw StateError('session-protocol server requires an authority');
    }
    _serverConfig = config;
    _socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    try {
      await config.fs.atomicWrite(config.advertisePath, _advertisement(server));
      appLogger.i(
        '[$_tag] advertised path=${config.advertisePath} port=${_socket!.port}',
      );
      _advertisementTimer ??= Timer.periodic(
        const Duration(seconds: 10),
        (_) => unawaited(_ensureAdvertisement(server, config)),
      );
    } on Object {
      await _socket?.close();
      _socket = null;
      _serverConfig = null;
      rethrow;
    }
    _role = SessionProtocolRole.server;
    appLogger.i(
      '[$_tag] role=server authority=${server.authorityId} epoch=${server.epoch}',
    );
    final socket = _socket!;
    _acceptLoop = () async {
      try {
        await for (final client in socket) {
          await _serve(client, server);
        }
      } on Object {
        // Closed by applyNone.
      }
    }();
  }

  Future<void> applyClient({
    required Future<SessionByteChannel> Function() open,
  }) async {
    await applyNone();
    _role = SessionProtocolRole.client;
    appLogger.i('[$_tag] role=client device=$deviceId');
    final client = SessionClientConnection(
      open: open,
      deviceId: deviceId,
      callbacks: SessionClientCallbacks(
        onSnapshot: (snapshots) {
          appLogger.i(
            '[$_tag] client snapshot sessions=${snapshots.length} '
            'ids=${snapshots.map((s) => s.sessionId).join(',')}',
          );
          remoteCubit.applySnapshots(snapshots);
        },
        onDelta: (delta) {
          appLogger.d(
            '[$_tag] client delta session=${delta.sessionId} '
            'rev=${delta.baseRevision}->${delta.revision} '
            'busy=${delta.seats.any((s) => s.isBusy)} removed=${delta.removed}',
          );
          remoteCubit.applyDelta(delta);
        },
        onContent: (invalidation) {
          appLogger.d(
            '[$_tag] client content session=${invalidation.sessionId} '
            'seq=${invalidation.seq}',
          );
          onContentInvalidated?.call(invalidation);
        },
        onAttention: (attention) {
          appLogger.i(
            '[$_tag] client attention session=${attention.sessionId} '
            'kind=${attention.kind}',
          );
          onAttention?.call(attention);
        },
        onReady: () => appLogger.i('[$_tag] client ready'),
        onError: (code, message) {
          appLogger.w('[$_tag] client error code=$code message=$message');
        },
        onClosed: () {
          appLogger.i('[$_tag] client closed');
          remoteCubit.clear();
        },
      ),
    );
    _client = client;
    await client.start();
  }

  Future<void> _ensureAdvertisement(
    SessionAuthority authority,
    SessionProtocolServerConfig config,
  ) async {
    if (_socket == null) return;
    try {
      final existing = await config.fs.readString(config.advertisePath);
      if (existing != null && existing.trim().isNotEmpty) return;
      await config.fs.atomicWrite(
        config.advertisePath,
        _advertisement(authority),
      );
      appLogger.i('[$_tag] re-advertised missing ${config.advertisePath}');
    } on Object catch (error, stackTrace) {
      appLogger.d(
        '[$_tag] advertisement refresh failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> applyNone() async {
    if (_role != SessionProtocolRole.none) {
      appLogger.i('[$_tag] role=none (was $_role)');
    }
    _advertisementTimer?.cancel();
    _advertisementTimer = null;
    _role = SessionProtocolRole.none;
    final client = _client;
    _client = null;
    await client?.stop();
    final socket = _socket;
    _socket = null;
    await socket?.close();
    await _acceptLoop;
    _acceptLoop = null;
    for (final server in List<SessionServer>.of(_servers)) {
      await server.stop();
    }
    _servers.clear();
    final config = _serverConfig;
    _serverConfig = null;
    if (config != null) {
      try {
        await config.fs.removeRecursive(config.advertisePath);
      } on Object catch (error, stackTrace) {
        appLogger.d(
          '[$_tag] advertisement remove failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    remoteCubit.clear();
  }

  Future<void> _serve(Socket socket, SessionAuthority authority) async {
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } on Object {
      // Best effort.
    }
    final channel = _SocketSessionByteChannel(socket);
    final server = SessionServer(
      channel: channel,
      authority: authority,
      deviceId: deviceId,
    );
    _servers.add(server);
    unawaited(
      server.done.whenComplete(() async {
        _servers.remove(server);
        await server.stop();
      }),
    );
    await server.start();
  }

  String _advertisement(SessionAuthority authority) {
    return '{"v":$sessionProtocolVersion,"bindHost":"127.0.0.1",'
        '"port":${_socket!.port},'
        '"pid":${_pid()},'
        '"authority":"${authority.authorityId}",'
        '"epoch":${authority.epoch},'
        '"startedAt":"${DateTime.now().toUtc().toIso8601String()}"}';
  }
}

final class _SocketSessionByteChannel implements SessionByteChannel {
  _SocketSessionByteChannel(this._socket) {
    _subscription = _socket.listen(
      (data) {
        if (!_incoming.isClosed) _incoming.add(data);
      },
      onDone: () {
        if (!_incoming.isClosed) unawaited(_incoming.close());
      },
      onError: (Object error, StackTrace stackTrace) {
        appLogger.w(
          '[session-protocol] socket error',
          error: error,
          stackTrace: stackTrace,
        );
        if (!_incoming.isClosed) unawaited(_incoming.close());
      },
      cancelOnError: true,
    );
  }

  final Socket _socket;
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  late final StreamSubscription<List<int>> _subscription;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  void add(List<int> data) => _socket.add(data);

  @override
  Future<void> close() async {
    await _subscription.cancel();
    if (!_incoming.isClosed) await _incoming.close();
    await _socket.close();
  }
}
