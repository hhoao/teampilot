import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../../models/ssh_profile.dart';
import '../ssh_transport_close.dart';
import 'ssh_worker_protocol.dart';
import 'ssh_worker_member_core.dart';
import 'ssh_worker_forward_core.dart';
import 'ssh_worker_shared_client.dart';
import 'ssh_worker_storage_backend.dart';
import 'ssh_worker_storage_core.dart';

/// Worker-local dartssh2 callbacks backed by UI-isolate challenge replies.
///
/// The caller supplies a UI-resolved [dialTarget] when it creates a worker
/// generation. The only private-key parse is in [openClient], after the PEM
/// and passphrase replies arrive in this worker isolate.
class SshWorkerConnectionCallbacks {
  const SshWorkerConnectionCallbacks({
    required this.profile,
    required this.dialTarget,
    required SshWorkerAuthChallengeHandler requestAuth,
  }) : _requestAuth = requestAuth;

  final SshProfile profile;
  final SshWorkerDialTarget dialTarget;
  final SshWorkerAuthChallengeHandler _requestAuth;

  Future<SSHClient> openClient({
    required Duration timeout,
    void Function(Object error, StackTrace stackTrace)? onKeepAliveFailed,
  }) async {
    final socket = await SSHSocket.connect(
      dialTarget.host,
      dialTarget.port,
      timeout: timeout,
    );
    Future<bool> hostKeyVerifier(String keyType, Uint8List fingerprint) async {
      final reply = await _requestAuth(
        SshWorkerAuthChallenge.hostKey(
          requestId: '',
          profileId: profile.id,
          keyType: keyType,
          fingerprint: fingerprint,
        ),
      );
      return reply.accepted ?? false;
    }

    SSHClient? client;
    void keepAliveFailed(Object error, StackTrace stackTrace) {
      onKeepAliveFailed?.call(error, stackTrace);
      // Keepalive failure means the channel is half-open. Closing the client
      // completes `done` and lets the owning core tear down/reconnect instead
      // of silently waiting for the next user IO to time out.
      unawaited(client?.close());
    }

    switch (profile.authType) {
      case SshAuthType.password:
        final password =
            (await _requestAuth(
              SshWorkerAuthChallenge.password(
                requestId: '',
                profileId: profile.id,
              ),
            )).secretValue ??
            '';
        client = SSHClient(
          socket,
          username: profile.username,
          onPasswordRequest: () => password,
          onVerifyHostKey: hostKeyVerifier,
          onKeepAliveFailed: keepAliveFailed,
          handshakeTimeout: timeout,
          authTimeout: timeout,
        );
        return client;
      case SshAuthType.privateKey:
        final pem = (await _requestAuth(
          SshWorkerAuthChallenge.privateKey(
            requestId: '',
            profileId: profile.id,
          ),
        )).secretValue;
        if (pem == null || pem.isEmpty) {
          throw StateError('Private key not found for profile ${profile.id}');
        }
        final passphrase = (await _requestAuth(
          SshWorkerAuthChallenge.privateKeyPassphrase(
            requestId: '',
            profileId: profile.id,
          ),
        )).secretValue;
        final identities = SSHKeyPair.fromPem(
          pem,
          passphrase == null || passphrase.isEmpty ? null : passphrase,
        );
        client = SSHClient(
          socket,
          username: profile.username,
          identities: identities,
          onVerifyHostKey: hostKeyVerifier,
          onKeepAliveFailed: keepAliveFailed,
          handshakeTimeout: timeout,
          authTimeout: timeout,
        );
        return client;
    }
  }
}

/// Serializable bootstrap data for a profile worker isolate.
class SshWorkerBootstrap {
  const SshWorkerBootstrap({required this.profileId, required this.uiPort});

  final String profileId;
  final SendPort uiPort;
}

/// Worker-side command actor for one SSH profile.
///
/// Owns storage, member, PTY, exec, and forwarding dartssh2 channels behind
/// the primitive isolate protocol. Unsupported commands fail explicitly rather
/// than exposing a UI-isolate bypass.
class SshProfileWorker {
  SshProfileWorker({
    required this.bootstrap,
    required this.send,
    SshWorkerForwardClientOpener? forwardClientOpener,
  }) : _forwardClientOpener = forwardClientOpener {
    _sharedClient = SshWorkerSharedClient(
      profileId: bootstrap.profileId,
      openClient:
          ({
            required SshProfile profile,
            required SshWorkerDialTarget target,
            required Duration timeout,
          }) => connectionCallbacks(
            profile: profile,
            dialTarget: target,
          ).openClient(timeout: timeout),
    );
  }

  final SshWorkerBootstrap bootstrap;
  final void Function(Object? message) send;
  final SshWorkerForwardClientOpener? _forwardClientOpener;
  late final SshWorkerSharedClient _sharedClient;

  ReceivePort? _commands;
  final Map<String, Completer<SshWorkerAuthReply>> _pendingAuthReplies = {};
  var _authRequestSequence = 0;
  var _stopping = false;
  SshWorkerStorageCore? _storageCore;
  Future<SshWorkerReply>? _storageInitialization;
  SshWorkerMemberCore? _memberCore;
  SshWorkerForwardCore? _forwardCore;
  final Set<Future<void>> _memberDispatches = {};
  final Set<Future<void>> _forwardDispatches = {};

  /// Creates worker-local dartssh2 callbacks wired to this actor's UI RPC.
  SshWorkerConnectionCallbacks connectionCallbacks({
    required SshProfile profile,
    required SshWorkerDialTarget dialTarget,
  }) => SshWorkerConnectionCallbacks(
    profile: profile,
    dialTarget: dialTarget,
    requestAuth: requestAuth,
  );

  /// Sends a correlated auth challenge and waits for the UI-isolate reply.
  Future<SshWorkerAuthReply> requestAuth(SshWorkerAuthChallenge challenge) {
    if (_stopping) {
      return Future<SshWorkerAuthReply>.error(
        StateError('SSH profile worker is shutting down'),
      );
    }
    if (challenge.profileId != bootstrap.profileId) {
      return Future<SshWorkerAuthReply>.error(
        StateError('SSH worker auth challenge profile mismatch'),
      );
    }
    final requestId = 'auth-${bootstrap.profileId}-${_authRequestSequence++}';
    final correlated = challenge.withRequestId(requestId);
    final completer = Completer<SshWorkerAuthReply>();
    _pendingAuthReplies[requestId] = completer;
    send(correlated.toWire());
    return completer.future;
  }

  /// Starts the command port and publishes its send port to the UI facade.
  void start() {
    if (_commands != null) {
      throw StateError('SSH profile worker has already started');
    }
    final commands = ReceivePort();
    _commands = commands;
    commands.listen(_onWireMessage);
    send({'type': 'ready', 'commandPort': commands.sendPort});
  }

  void _onWireMessage(Object? wire) {
    if (wire is Map && wire['type'] == 'authReply') {
      _acceptAuthReply(wire);
      return;
    }
    SshWorkerRequest request;
    try {
      request = SshWorkerRequest.fromWire(wire);
    } on FormatException {
      final requestId = _requestIdFromWire(wire);
      if (requestId != null) {
        _sendWireFailure(
          requestId,
          'invalid_storage_request',
          'Invalid worker request',
        );
      }
      return;
    }

    if (_stopping) {
      _sendFailure(request, 'worker_shutting_down', 'Worker is shutting down');
      return;
    }
    if (request.operation == SshWorkerOperation.shutdown) {
      _stopping = true;
      unawaited(_shutdown(request));
      return;
    }
    unawaited(_dispatch(request));
  }

  Future<void> _dispatch(SshWorkerRequest request) async {
    if (_isMemberOperation(request.operation)) {
      final core = _memberCore ??= SshWorkerMemberCore(
        profileId: bootstrap.profileId,
        openClient: ({required profile, required target, required timeout}) =>
            _sharedClient.acquire(
              profile: profile,
              target: target,
              timeout: timeout,
            ),
        sendEvent: (event) => send(event.toWire()),
      );
      late Future<void> dispatch;
      dispatch = core.handle(request).then<void>((reply) {
        send(reply.toWire());
      });
      _memberDispatches.add(dispatch);
      try {
        await dispatch;
      } finally {
        _memberDispatches.remove(dispatch);
      }
      return;
    }
    if (_isForwardOperation(request.operation)) {
      final openForwardClient =
          _forwardClientOpener ??
          ({
            required SshProfile profile,
            required SshWorkerDialTarget target,
            required Duration timeout,
          }) async => DartSshWorkerForwardClient(
            await _sharedClient.acquire(
              profile: profile,
              target: target,
              timeout: timeout,
            ),
            ownsClient: false,
          );
      final core = _forwardCore ??= SshWorkerForwardCore(
        profileId: bootstrap.profileId,
        openClient: openForwardClient,
        sendEvent: (event) => send(event.toWire()),
      );
      late Future<void> dispatch;
      dispatch = core.handle(request).then<void>((reply) {
        send(reply.toWire());
      });
      _forwardDispatches.add(dispatch);
      try {
        await dispatch;
      } finally {
        _forwardDispatches.remove(dispatch);
      }
      return;
    }
    if (!_isStorageOperation(request.operation)) {
      _sendFailure(
        request,
        'unsupported_operation',
        'Unsupported worker operation',
      );
      return;
    }
    if (request.operation == SshWorkerOperation.disconnectStorage) {
      await _disconnectStorage();
      send(SshWorkerReply.success(request.requestId).toWire());
      return;
    }
    var core = _storageCore;
    if (core == null &&
        request.operation != SshWorkerOperation.connectStorage) {
      _sendFailure(
        request,
        'storage_not_connected',
        'Storage must be connected before use',
      );
      return;
    }
    if (core == null) {
      try {
        final reply = await _beginStorageInitialization(request);
        send(
          SshWorkerReply.success(
            request.requestId,
            result: reply.result,
          ).toWire(),
        );
      } on _StorageInitializationFailure catch (error) {
        _sendFailure(request, error.code, error.message);
      } on FormatException {
        _sendFailure(
          request,
          'invalid_storage_request',
          'Invalid storage connection request',
        );
      } on Object {
        _sendFailure(
          request,
          'transport_error',
          'Invalid storage connection request',
        );
      }
      return;
    }
    final reply = await core.handle(request);
    send(reply.toWire());
  }

  Future<SshWorkerReply> _beginStorageInitialization(SshWorkerRequest request) {
    final existing = _storageInitialization;
    if (existing != null) return existing;
    final initialization = _initializeStorage(request);
    _storageInitialization = initialization;
    initialization.then<void>(
      (_) {
        if (identical(_storageInitialization, initialization)) {
          _storageInitialization = null;
        }
      },
      onError: (Object _, StackTrace __) {
        if (identical(_storageInitialization, initialization)) {
          _storageInitialization = null;
        }
      },
    );
    return initialization;
  }

  Future<SshWorkerReply> _initializeStorage(SshWorkerRequest request) async {
    final core = _createStorageCore(request);
    _storageCore = core;
    try {
      final reply = await core.handle(request);
      if (reply.kind != SshWorkerReplyKind.success) {
        _storageCore = null;
        core.shutdown();
        throw _StorageInitializationFailure(
          reply.error?.code ?? 'transport_error',
          reply.error?.message ?? 'Storage connection failed',
        );
      }
      return reply;
    } catch (_) {
      if (identical(_storageCore, core)) {
        _storageCore = null;
        core.shutdown();
      }
      rethrow;
    }
  }

  /// Closes only the storage plane while keeping member/PTY/forward sessions
  /// on the same worker generation alive.
  Future<void> _disconnectStorage() async {
    final initialization = _storageInitialization;
    if (initialization != null) {
      try {
        await initialization;
      } on Object {
        // Initialization already owns its cleanup path.
      }
    }
    _storageCore?.shutdown();
    _storageCore = null;
    _storageInitialization = null;
  }

  Future<void> _shutdown(SshWorkerRequest request) async {
    _forwardCore?.beginShutdown();
    final initialization = _storageInitialization;
    if (initialization != null) {
      try {
        await initialization;
      } on Object {
        // The initialization path owns cleanup and the shutdown still closes
        // the worker-held core below.
      }
    }
    _storageCore?.shutdown();
    _storageCore = null;
    await Future.wait(_memberDispatches.toList(growable: false));
    await _memberCore?.shutdown();
    _memberCore = null;
    await Future.wait(_forwardDispatches.toList(growable: false));
    await _forwardCore?.shutdown();
    _forwardCore = null;
    await _sharedClient.close();
    _failPendingAuthReplies();
    send(SshWorkerReply.success(request.requestId).toWire());
    _commands?.close();
  }

  bool _isStorageOperation(SshWorkerOperation operation) => switch (operation) {
    SshWorkerOperation.connectStorage ||
    SshWorkerOperation.disconnectStorage ||
    SshWorkerOperation.runStorage ||
    SshWorkerOperation.openSftpRead ||
    SshWorkerOperation.readSftpChunk ||
    SshWorkerOperation.openSftpWrite ||
    SshWorkerOperation.writeSftpChunk ||
    SshWorkerOperation.closeSftpStream ||
    SshWorkerOperation.acknowledgeSftpChunk ||
    SshWorkerOperation.statSftp ||
    SshWorkerOperation.listSftpDirectory ||
    SshWorkerOperation.readlinkSftp ||
    SshWorkerOperation.realpathSftp ||
    SshWorkerOperation.mkdirSftp ||
    SshWorkerOperation.removeSftp ||
    SshWorkerOperation.cancelRequest => true,
    _ => false,
  };

  bool _isMemberOperation(SshWorkerOperation operation) => switch (operation) {
    SshWorkerOperation.openMember ||
    SshWorkerOperation.runMember ||
    SshWorkerOperation.startMemberExec ||
    SshWorkerOperation.writeMemberExec ||
    SshWorkerOperation.closeMemberExecStdin ||
    SshWorkerOperation.killMemberExec ||
    SshWorkerOperation.acknowledgeExecOutput ||
    SshWorkerOperation.openPty ||
    SshWorkerOperation.writePty ||
    SshWorkerOperation.resizePty ||
    SshWorkerOperation.acknowledgePtyOutput ||
    SshWorkerOperation.closeChannel => true,
    _ => false,
  };

  bool _isForwardOperation(SshWorkerOperation operation) => switch (operation) {
    SshWorkerOperation.openForwardLocal ||
    SshWorkerOperation.openForwardRemote ||
    SshWorkerOperation.writeForwardChannel ||
    SshWorkerOperation.acknowledgeForwardOutput ||
    SshWorkerOperation.closeForwardChannel ||
    SshWorkerOperation.closeForward => true,
    _ => false,
  };

  SshWorkerStorageCore _createStorageCore(SshWorkerRequest request) {
    final rawProfile = request.args['profile'];
    final rawTarget = request.args['target'];
    if (rawProfile is! Map || rawTarget is! Map) throw const FormatException();
    final profileMap = rawProfile.cast<String, Object?>();
    _validateStorageProfile(profileMap);
    final profile = SshProfile.fromJson(profileMap);
    final target = SshWorkerDialTarget.fromWire(rawTarget);
    if (profile.id != bootstrap.profileId ||
        profile.host.isEmpty ||
        profile.username.isEmpty ||
        profile.port < 1 ||
        profile.port > 65535 ||
        target.host.isEmpty ||
        target.port < 1 ||
        target.port > 65535) {
      throw const FormatException();
    }
    late SshWorkerStorageCore core;
    final backend = SshWorkerDartStorageBackend(
      openClient: (connectRequest) => _sharedClient.acquire(
        profile: profile,
        target: target,
        timeout: _timeout(connectRequest),
      ),
      onClosed: () => core.invalidate(SshTransportCloseReason.transportError),
    );
    core = SshWorkerStorageCore(
      backend: backend,
      sendEvent: (event) => send(event.toWire()),
    );
    return core;
  }

  Duration _timeout(SshWorkerRequest request) => Duration(
    milliseconds: request.args['timeoutMs'] is int
        ? request.args['timeoutMs']! as int
        : const Duration(seconds: 30).inMilliseconds,
  );

  void _validateStorageProfile(Map<String, Object?> profile) {
    for (final field in ['id', 'name', 'host', 'username']) {
      final value = profile[field];
      if (value is! String || value.isEmpty) throw const FormatException();
    }
    final port = profile['port'];
    if (port is! int || port < 1 || port > 65535) {
      throw const FormatException();
    }
    final authType = profile['authType'];
    if (authType is! String ||
        !SshAuthType.values.any((value) => value.name == authType)) {
      throw const FormatException();
    }
  }

  void _acceptAuthReply(Object? wire) {
    SshWorkerAuthReply reply;
    try {
      reply = SshWorkerAuthReply.fromWire(wire);
    } on FormatException {
      return;
    }
    final completer = _pendingAuthReplies.remove(reply.requestId);
    if (completer == null) return;
    if (reply.errorCode != null) {
      completer.completeError(StateError('SSH worker auth reply failed'));
      return;
    }
    completer.complete(reply);
  }

  void _failPendingAuthReplies() {
    final pending = _pendingAuthReplies.values.toList(growable: false);
    _pendingAuthReplies.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('SSH profile worker closed'));
      }
    }
  }

  void _sendFailure(SshWorkerRequest request, String code, String message) {
    _sendWireFailure(request.requestId, code, message);
  }

  String? _requestIdFromWire(Object? wire) {
    if (wire is! Map) return null;
    final requestId = wire['requestId'];
    return requestId is String && requestId.isNotEmpty ? requestId : null;
  }

  void _sendWireFailure(String requestId, String code, String message) {
    send(
      SshWorkerReply.failure(
        requestId,
        SshWorkerErrorRecord(code: code, message: message),
      ).toWire(),
    );
  }
}

final class _StorageInitializationFailure implements Exception {
  const _StorageInitializationFailure(this.code, this.message);

  final String code;
  final String message;
}
