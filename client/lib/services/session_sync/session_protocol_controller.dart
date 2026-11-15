import 'dart:async';
import 'dart:io';

import '../../cubits/session_remote_activity_cubit.dart';
import '../../utils/logging/logger.dart';
import '../attention/attention_batch.dart';
import '../attention/attention_cursor.dart';
import '../attention/attention_inbox.dart';
import '../chat/rewind/edit/edit_transport.dart';
import 'remote_seat_edit_transport.dart';
import 'session_edit_executor.dart';
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
    this.onContentDelta,
    this.onSessionList,
    this.attentionInbox,
    this.isExpectedFailure,
    this.waitForRecovery,
    int Function()? pid,
  }) : _pid = pid ?? _currentPid;

  static const _tag = 'session-protocol';

  final String deviceId;
  final SessionAuthority? authority;
  final SessionRemoteActivityCubit remoteCubit;
  final void Function(SessionContentInvalidated invalidation)?
  onContentInvalidated;
  final void Function(SessionContentDelta delta)? onContentDelta;
  final void Function(SessionListDelta delta)? onSessionList;
  final AttentionInbox? attentionInbox;
  final bool Function(Object error)? isExpectedFailure;
  final Future<bool> Function(Object error)? waitForRecovery;
  final int Function() _pid;

  SessionProtocolRole _role = SessionProtocolRole.none;
  String _homeId = '';
  Future<void> _attentionQueue = Future<void>.value();
  int _attentionConnectionGeneration = 0;
  bool _attentionPaused = false;
  ServerSocket? _socket;
  SessionProtocolServerConfig? _serverConfig;
  final Set<SessionServer> _servers = {};
  SessionClientConnection? _client;
  final Set<String> _pendingRefreshWorkspaces = {};
  final List<
    ({String workspaceId, String sessionId, Map<String, Object?> entry})
  >
  _pendingCreates = [];
  final List<({String workspaceId, String sessionId})> _pendingRemoves = [];
  Future<void>? _acceptLoop;
  Timer? _advertisementTimer;

  SessionProtocolRole get role => _role;

  bool get isClient => _role == SessionProtocolRole.client;

  /// The transport that delegates an edited-message resend to the desktop.
  ///
  /// Null unless this process is a connected client *and* the authority reports
  /// the seat: delegating a seat whose runtime the phone started over SSH would
  /// make the desktop spawn a second runtime for the same work tree.
  SeatEditTransport? editTransportFor({
    required String sessionId,
    required String memberId,
  }) {
    final client = _client;
    final ownsSeat =
        remoteCubit.state
            .session(sessionId)
            ?.seats
            .any((seat) => seat.memberId == memberId) ??
        false;
    final executor = resolveEditExecutor(
      isClient: _role == SessionProtocolRole.client && (client?.isReady ?? false),
      authorityOwnsSeat: ownsSeat,
    );
    if (executor != EditExecutor.authority || client == null) return null;
    return RemoteSeatEditTransport(
      connection: client,
      activity: remoteCubit,
      sessionId: sessionId,
      memberId: memberId,
    );
  }

  Future<SessionIntentResult> createSession({
    required String workspaceId,
    required String sessionId,
    required Map<String, Object?> entry,
  }) async {
    final wid = workspaceId.trim();
    final sid = sessionId.trim();
    if (wid.isEmpty || sid.isEmpty) {
      return const SessionIntentResult(
        id: '',
        status: SessionIntentStatus.rejected,
        code: 'session_row_required',
      );
    }
    if (_role == SessionProtocolRole.server) {
      return const SessionIntentResult(
        id: '',
        status: SessionIntentStatus.rejected,
        code: 'server_role',
      );
    }
    final pending = (workspaceId: wid, sessionId: sid, entry: entry);
    final client = _client;
    if (client == null || !client.isReady) {
      _pendingCreates.add(pending);
      return const SessionIntentResult(
        id: '',
        status: SessionIntentStatus.rejected,
        code: 'not_connected',
      );
    }
    final result = await client.createSession(
      workspaceId: wid,
      sessionId: sid,
      entry: entry,
    );
    if (!result.ok && result.code == 'not_connected') {
      _pendingCreates.add(pending);
    }
    return result;
  }

  Future<SessionIntentResult> removeSession({
    required String workspaceId,
    required String sessionId,
  }) async {
    final wid = workspaceId.trim();
    final sid = sessionId.trim();
    if (wid.isEmpty || sid.isEmpty) {
      return const SessionIntentResult(
        id: '',
        status: SessionIntentStatus.rejected,
        code: 'session_row_required',
      );
    }
    if (_role == SessionProtocolRole.server) {
      return const SessionIntentResult(
        id: '',
        status: SessionIntentStatus.rejected,
        code: 'server_role',
      );
    }
    final pending = (workspaceId: wid, sessionId: sid);
    final client = _client;
    if (client == null || !client.isReady) {
      _pendingRemoves.add(pending);
      return const SessionIntentResult(
        id: '',
        status: SessionIntentStatus.rejected,
        code: 'not_connected',
      );
    }
    final result = await client.removeSession(workspaceId: wid, sessionId: sid);
    if (!result.ok && result.code == 'not_connected') {
      _pendingRemoves.add(pending);
    }
    return result;
  }

  Future<SessionIntentResult> refreshSessions({
    required String workspaceId,
  }) async {
    final id = workspaceId.trim();
    if (id.isEmpty) {
      return const SessionIntentResult(
        id: '',
        status: SessionIntentStatus.rejected,
        code: 'workspace_required',
      );
    }
    if (_role == SessionProtocolRole.server) {
      return const SessionIntentResult(
        id: '',
        status: SessionIntentStatus.rejected,
        code: 'server_role',
      );
    }
    final client = _client;
    if (client == null || !client.isReady) {
      // Created while the mobile client was still connecting: replay once the
      // session plane is ready so the desktop eventually sees the new session.
      _pendingRefreshWorkspaces.add(id);
      return const SessionIntentResult(
        id: '',
        status: SessionIntentStatus.rejected,
        code: 'not_connected',
      );
    }
    final result = await client.refreshSessions(workspaceId: id);
    if (!result.ok && result.code == 'not_connected') {
      _pendingRefreshWorkspaces.add(id);
    }
    return result;
  }

  Future<void> _flushPendingRefreshes() async {
    if (_role != SessionProtocolRole.client) return;
    final client = _client;
    if (client == null || !client.isReady) return;
    final pending = _pendingRefreshWorkspaces.toList();
    _pendingRefreshWorkspaces.clear();
    for (final id in pending) {
      final result = await client.refreshSessions(workspaceId: id);
      if (!result.ok && result.code == 'not_connected') {
        _pendingRefreshWorkspaces.add(id);
      }
    }
  }

  Future<void> _flushPendingCreates() async {
    if (_role != SessionProtocolRole.client) return;
    final client = _client;
    if (client == null || !client.isReady) return;
    final pending = _pendingCreates.toList();
    _pendingCreates.clear();
    for (final item in pending) {
      final result = await client.createSession(
        workspaceId: item.workspaceId,
        sessionId: item.sessionId,
        entry: item.entry,
      );
      if (!result.ok && result.code == 'not_connected') {
        _pendingCreates.add(item);
      }
    }
  }

  Future<void> _flushPendingRemoves() async {
    if (_role != SessionProtocolRole.client) return;
    final client = _client;
    if (client == null || !client.isReady) return;
    final pending = _pendingRemoves.toList();
    _pendingRemoves.clear();
    for (final item in pending) {
      final result = await client.removeSession(
        workspaceId: item.workspaceId,
        sessionId: item.sessionId,
      );
      if (!result.ok && result.code == 'not_connected') {
        _pendingRemoves.add(item);
      }
    }
  }

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
    _pendingRefreshWorkspaces.clear();
    _pendingCreates.clear();
    _pendingRemoves.clear();
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
    required String homeId,
  }) async {
    await applyNone();
    _homeId = homeId.trim();
    _attentionConnectionGeneration++;
    _attentionPaused = false;
    _role = SessionProtocolRole.client;
    appLogger.i('[$_tag] role=client device=$deviceId home=$_homeId');
    late final SessionClientConnection client;
    client = SessionClientConnection(
      open: open,
      deviceId: deviceId,
      attentionCursors: _attentionCursors,
      isExpectedFailure: isExpectedFailure,
      waitForRecovery: waitForRecovery,
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
        onContentDelta: (delta) {
          appLogger.d(
            '[$_tag] client content-delta session=${delta.sessionId} '
            'kind=${delta.kind} seq=${delta.seq} bytes=${delta.payload.length}',
          );
          onContentDelta?.call(delta);
        },
        onSessionList: (delta) {
          appLogger.i(
            '[$_tag] client session-list workspace=${delta.workspaceId} '
            'rev=${delta.revision} upserted=${delta.upserted.length} '
            'removed=${delta.removed.length}',
          );
          onSessionList?.call(delta);
        },
        onAttentionBatch: (batch) {
          appLogger.i(
            '[$_tag] client attention authority=${batch.authorityId} '
            'epoch=${batch.epoch} from=${batch.fromSeq} to=${batch.toSeq} '
            'count=${batch.events.length} gap=${batch.gap}',
          );
          _enqueueAttentionBatch(batch, client: client);
        },
        onReady: () {
          appLogger.i('[$_tag] client ready');
          _resetAttentionCursorIfEpochMoved();
          unawaited(_flushPendingRefreshes());
          unawaited(_flushPendingCreates());
          unawaited(_flushPendingRemoves());
        },
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

  Map<String, AttentionCursor> _attentionCursors() {
    final inbox = attentionInbox;
    if (inbox == null || _homeId.isEmpty) return const {};
    final cursor = inbox.cursorFor(_homeId);
    return cursor == null ? const {} : {cursor.authorityId: cursor};
  }

  void _resetAttentionCursorIfEpochMoved() {
    final inbox = attentionInbox;
    final cursor = inbox?.cursorFor(_homeId);
    final epoch = _client?.client?.epoch;
    if (inbox == null ||
        cursor == null ||
        epoch == null ||
        cursor.epoch == epoch) {
      return;
    }
    unawaited(inbox.clearCursor(_homeId));
  }

  void _enqueueAttentionBatch(
    AttentionBatch batch, {
    required SessionClientConnection client,
  }) {
    final capturedHomeId = _homeId;
    final generation = _attentionConnectionGeneration;
    _attentionQueue = _attentionQueue
        .catchError((Object _) {})
        .then(
          (_) => _handleAttentionBatch(
            batch,
            homeId: capturedHomeId,
            client: client,
            generation: generation,
          ),
        )
        .catchError((Object error, StackTrace stackTrace) {
          appLogger.w(
            '[$_tag] attention batch failed',
            error: error,
            stackTrace: stackTrace,
          );
        });
  }

  Future<void> _handleAttentionBatch(
    AttentionBatch batch, {
    required String homeId,
    required SessionClientConnection client,
    required int generation,
  }) async {
    if (_attentionPaused) return;
    if (generation != _attentionConnectionGeneration) return;
    if (!identical(_client, client) || homeId.isEmpty) return;
    final inbox = attentionInbox;
    if (inbox == null) return;
    try {
      await inbox.ingest(homeId, batch.events);
      if (batch.gap) await inbox.skipGap(homeId, batch);
    } on AttentionPersistenceException catch (error, stackTrace) {
      appLogger.w(
        '[$_tag] attention persistence failed; pausing until reconnect '
        'home=$homeId authority=${batch.authorityId} epoch=${batch.epoch} '
        'to=${batch.toSeq}',
        error: error,
        stackTrace: stackTrace,
      );
      _attentionPaused = true;
      return;
    }
    if (_attentionPaused) return;
    if (generation != _attentionConnectionGeneration) return;
    if (!identical(_client, client)) return;
    client.client?.sendAttentionAck(
      authorityId: batch.authorityId,
      epoch: batch.epoch,
      seq: batch.toSeq,
    );
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
    _attentionConnectionGeneration++;
    await client?.stop();
    await _attentionQueue;
    _homeId = '';
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
