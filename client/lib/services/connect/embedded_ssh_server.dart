/// The desktop's embedded SSH server: one [SSHServer] instance, bound on the
/// wildcard address with the persisted embedded port, authenticating phones
/// solely against the [PairedDeviceStore] key registry.
///
/// Trust is fail-closed: `authenticate` consults
/// [PairedDeviceStore.isValidDeviceKey] and nothing else, so an unregistered
/// (or revoked) key can never log in. Revocation also tears down the revoked
/// device's established connections immediately — every authenticated
/// connection is recorded through the `onAuthenticated` hook and evicted when
/// the device registry changes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' show SSHSocket;
import 'package:path/path.dart' as p;
import 'package:tp_sshd/tp_sshd.dart';

import '../../utils/logging/logger_utils.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart' show AppPaths;
import 'connect_settings_store.dart';
import 'embedded_host_key_store.dart';
import 'embedded_process_factories.dart';
import 'embedded_sftp_filesystem.dart';
import 'paired_device_store.dart';

/// The surface the app consumes (Task 10's ConnectAgent); implemented by
/// [EmbeddedSshServer].
abstract class EmbeddedSshServerHandle {
  /// Whether [EmbeddedSshServer.start] currently holds a listener.
  bool get isListening;

  /// The actually bound port — not the requested one, so an ephemeral
  /// `portOverride: 0` (tests) or a re-picked port is reported correctly.
  int get port;

  /// OpenSSH-style SHA256 fingerprints of the host key, for the pairing
  /// offer's verification UI.
  List<String> get hostKeyFingerprints;

  /// Stops and starts the server — the retry affordance for a failed start
  /// (e.g. the persisted port was occupied and the re-pick also failed).
  Future<void> restart();
}

/// Thrown when the embedded server cannot bind a port — after the single
/// re-pick retry on a persisted-port conflict. Non-fatal for the app: the
/// caller catches it and surfaces the retry affordance.
class EmbeddedSshServerStartException implements Exception {
  EmbeddedSshServerStartException(this.message);

  final String message;

  @override
  String toString() => 'EmbeddedSshServerStartException: $message';
}

/// Owns the tp_sshd instance and its dart:io resources: the listener socket,
/// the persisted host key, the settings store, and the device-registry
/// subscription that powers revocation teardown.
class EmbeddedSshServer implements EmbeddedSshServerHandle {
  EmbeddedSshServer({
    required Filesystem fs,
    required String appDataRoot,
    required PairedDeviceStore deviceStore,
    required this.username,
    required this.homePath,
    p.Context? pathContext,
    InternetAddress? bindAddress,
    int? portOverride,
    PtySpawner? ptySpawner,
  }) : _fs = fs,
       _appDataRoot = appDataRoot,
       _deviceStore = deviceStore,
       _bindAddress = bindAddress ?? InternetAddress.anyIPv4,
       _portOverride = portOverride,
       _ptySpawner = ptySpawner,
       _pathContext = pathContext ?? AppPaths.pathContextForDataRoot(
         appDataRoot,
       );

  final Filesystem _fs;
  final String _appDataRoot;
  final PairedDeviceStore _deviceStore;
  final InternetAddress _bindAddress;
  final int? _portOverride;

  /// How `shell` requests spawn their pty. Production leaves this null
  /// (flutter_pty's real pseudo-terminal); the integration test injects a
  /// dart:io `Process`-backed spawner because flutter_pty needs the Flutter
  /// engine a plain test runner cannot provide.
  final PtySpawner? _ptySpawner;
  final p.Context _pathContext;

  /// The only username this server authenticates (the native user the app
  /// runs as; resolved by the Task 10 call site in app_shell).
  final String username;

  /// The native user home; the anchor for windows-context SFTP paths.
  final String homePath;

  ServerSocket? _listener;
  SSHServer? _server;
  StreamController<SSHSocket>? _connections;
  StreamSubscription<void>? _registrySubscription;
  EmbeddedHostKey? _hostKey;
  int _port = 0;

  /// Live authenticated connections, with the device each authenticated as
  /// and the public key line it used.
  final _connectionDevices = <SSHServerConnection, _DeviceConnection>{};

  @override
  bool get isListening => _listener != null;

  @override
  int get port => _listener?.port ?? _port;

  @override
  List<String> get hostKeyFingerprints =>
      _hostKey == null ? const [] : [_hostKey!.fingerprint];

  /// Loads (or generates) the host key, binds the listener, and starts the
  /// [SSHServer] over the accepted sockets.
  ///
  /// On a bind conflict with the persisted port, the port is re-picked once
  /// (persisting the replacement) and the bind retried; a second failure —
  /// or any failure with an explicit [portOverride] — throws
  /// [EmbeddedSshServerStartException].
  Future<void> start() async {
    if (isListening) {
      throw StateError('EmbeddedSshServer is already listening');
    }
    final hostKey = await EmbeddedHostKeyStore(
      fs: _fs,
      appDataRoot: _appDataRoot,
    ).loadOrCreate();
    _hostKey = hostKey;
    final settings = ConnectSettingsStore(fs: _fs, appDataRoot: _appDataRoot);
    final requestedPort =
        _portOverride ?? await settings.loadOrCreateEmbeddedPort();
    final listener = await _bindWithRetry(settings, requestedPort);
    _listener = listener;
    _port = listener.port;

    final connections = StreamController<SSHSocket>();
    _connections = connections;
    listener.listen((socket) => connections.add(_AcceptedSocket(socket)));

    _server = await SSHServer.bind(
      StreamIterator(connections.stream),
      config: SSHServerConfig(
        hostKeyPair: hostKey.keyPair,
        expectedUsername: username,
        authenticate: (request) async => _deviceStore.isValidDeviceKey(
          _opensshLineFor(request.algorithm, request.publicKey),
        ),
        processFactory: embeddedProcessFactory(),
        ptyFactory: embeddedPtyFactory(spawner: _ptySpawner),
        hostInfo: _hostInfo,
        sftpFileSystem: EmbeddedSftpFilesystem(
          pathContext: _pathContext,
          homePath: homePath,
        ),
        bindServerSocket: (address, port) async =>
            _IoServerSocketHandle(await ServerSocket.bind(address, port)),
        onAuthenticated: _recordDeviceConnection,
        printDebug: _printDebug,
      ),
    );

    _registrySubscription = _deviceStore.deviceRegistryChanged.listen(
      (_) => _evictRevokedDevices(),
    );
  }

  /// Binds [_bindAddress]:[port], re-picking once on a persisted-port
  /// conflict.
  Future<ServerSocket> _bindWithRetry(
    ConnectSettingsStore settings,
    int port,
  ) async {
    try {
      return await ServerSocket.bind(_bindAddress, port);
    } on SocketException catch (error) {
      if (_portOverride != null) {
        throw EmbeddedSshServerStartException(
          'could not bind ${_bindAddress.address}:$port ($error)',
        );
      }
      final repicked = await settings.repickEmbeddedPort();
      try {
        return await ServerSocket.bind(_bindAddress, repicked);
      } on SocketException catch (retryError) {
        throw EmbeddedSshServerStartException(
          'could not bind ${_bindAddress.address}:$repicked after re-pick '
          '($retryError)',
        );
      }
    }
  }

  /// Stops the server: cancels the registry subscription, closes the SSH
  /// server, the listener, and the accepted-socket stream.
  Future<void> stop() async {
    await _registrySubscription?.cancel();
    _registrySubscription = null;
    await _server?.close();
    _server = null;
    await _listener?.close();
    _listener = null;
    _port = 0;
    await _connections?.close();
    _connections = null;
    _connectionDevices.clear();
  }

  /// Stops and starts again (the retry affordance for a start failure).
  Future<void> restart() async {
    await stop();
    await start();
  }

  /// Revokes [deviceId] in the device store. The registry-changed
  /// listener tears down any live connection that device still holds.
  Future<bool> revokeDevice(String deviceId) {
    return _deviceStore.revokeDevice(deviceId);
  }

  /// Records which device authenticated on [connection], so revocation can
  /// find and close it later.
  Future<void> _recordDeviceConnection(
    SSHServerConnection connection,
    SSHServerAuthRequest request,
  ) async {
    final publicKeyLine = _opensshLineFor(request.algorithm, request.publicKey);
    // Record synchronously — before any await — so a revoke landing while the
    // registry lookup below is still in flight finds this connection in the
    // map and evicts it. There is no window between the userauth success and
    // the record.
    final entry = _DeviceConnection(publicKeyLine: publicKeyLine);
    _connectionDevices[connection] = entry;
    unawaited(
      connection.done.whenComplete(() => _connectionDevices.remove(connection)),
    );
    // Last-match-wins if two devices ever share one key blob — accepted per
    // the Task 3 review; the store owns registry semantics either way.
    final deviceId = await _deviceStore.deviceIdForPublicKey(publicKeyLine);
    if (deviceId == null) {
      // The key that just authenticated no longer resolves to a registered
      // device — a revoke (or re-pair) raced the lookup. Fail closed: the
      // connection is torn down, exactly as if the registry change had found
      // it recorded. (If eviction already closed it, the entry is gone and
      // there is nothing to do.)
      if (_connectionDevices.remove(connection) != null) {
        AppLogger.instance.i(
          'embedded ssh: closing connection whose device key was revoked '
          'during authentication',
        );
        unawaited(connection.close());
      }
      return;
    }
    entry.deviceId = deviceId;
  }

  /// Closes every recorded connection whose key no longer resolves to a
  /// registered device — its entry was revoked (or replaced by a re-pair).
  Future<void> _evictRevokedDevices() async {
    for (final entry in Map.of(_connectionDevices).entries) {
      final owner = await _deviceStore.deviceIdForPublicKey(
        entry.value.publicKeyLine,
      );
      if (owner != null) continue;
      _connectionDevices.remove(entry.key);
      AppLogger.instance.i(
        'embedded ssh: closing connection of revoked device '
        "'${entry.value.deviceId ?? 'unknown'}'",
      );
      unawaited(entry.key.close());
    }
  }

  /// The OpenSSH one-line form of a wire public key — the format
  /// [PairedDeviceStore.isValidDeviceKey] parses.
  static String _opensshLineFor(String algorithm, List<int> publicKey) =>
      '$algorithm ${base64.encode(publicKey)}';

  static void _printDebug(String? message) {
    // Keep the log readable: the transport traces every packet loop.
    if (message == null || message.contains('_processPackets')) return;
    AppLogger.instance.d('tp_sshd: $message');
  }
}

/// A device's hold on one live connection.
///
/// [deviceId] is `null` until the record-time registry lookup resolves — and
/// stays `null` forever if a revoke raced that lookup, in which case the
/// connection is closed fail-closed anyway.
class _DeviceConnection {
  _DeviceConnection({required this.publicKeyLine});

  final String publicKeyLine;
  String? deviceId;
}

/// Snapshot of host facts for the `tp1:` host-info query, answered by the
/// server itself (never by spawning a process).
SSHHostInfo _hostInfo() => SSHHostInfo(
      platform: Platform.operatingSystem,
      osUser: Platform.environment['USER'] ?? 'unknown',
      elevated: false,
      inDocker: File('/.dockerenv').existsSync(),
      shell: Platform.environment['SHELL'] ?? '/bin/sh',
    );

// ---------------------------------------------------------------------------
// Socket adapters: dart:io types onto the tp_sshd seams
// (ported from the tp_sshd demo server, where they passed real-client
// testing; keep in sync with example/demo_sshd.dart)
// ---------------------------------------------------------------------------

/// An accepted [Socket] exposed as the [SSHSocket] the server consumes.
class _AcceptedSocket implements SSHSocket {
  _AcceptedSocket(this._socket);

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

/// A real [ServerSocket] behind one `tcpip-forward` request.
class _IoServerSocketHandle implements ServerSocketHandle {
  _IoServerSocketHandle(this._socket);

  final ServerSocket _socket;

  @override
  int get port => _socket.port;

  @override
  Stream<ForwardConnection> get connections =>
      _socket.map(_IoForwardConnection.new);

  @override
  Future<void> close() => _socket.close();
}

/// One accepted forwarded TCP connection.
class _IoForwardConnection implements ForwardConnection {
  _IoForwardConnection(this._socket);

  final Socket _socket;

  @override
  Stream<Uint8List> get input => _socket;

  @override
  StreamSink<List<int>> get output => _socket;

  @override
  Future<void> get done => _socket.done;

  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;

  @override
  int get remotePort => _socket.remotePort;

  @override
  void destroy() => _socket.destroy();
}
