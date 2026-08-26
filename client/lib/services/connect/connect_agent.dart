import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:synchronized/synchronized.dart';

import '../../models/ssh_reachability.dart';
import '../io/filesystem.dart';
import 'authorized_keys_file.dart';
import 'connect_relay_client.dart';
import 'connect_settings_store.dart';
import 'paired_device_store.dart';
import 'pairing_certificate.dart';
import 'pairing_http.dart';
import 'pairing_token_gate.dart';
import 'ssh_pairing_offer.dart';
import 'sshd_presence.dart';

typedef PairingHttpRespond =
    Future<void> Function({
      required int statusCode,
      required Map<String, Object?> body,
    });

class PairingHttpRequest {
  const PairingHttpRequest({
    required this.method,
    required this.uri,
    required this.body,
    required this.respond,
  });

  final String method;
  final Uri uri;
  final PairingPostBody? body;
  final PairingHttpRespond respond;
}

class PairingBinding {
  const PairingBinding({
    required this.address,
    required this.port,
    required Future<void> Function() close,
    required this.requests,
  }) : _close = close;

  final InternetAddress address;
  final int port;
  final Future<void> Function() _close;
  final Stream<PairingHttpRequest> requests;

  Future<void> close() => _close();
}

typedef PairingBind =
    Future<PairingBinding> Function(InternetAddress address, Object tlsContext);
typedef StableConnectHostId = Future<String> Function(String appDataRoot);
typedef RelaySocketSeam = Future<WebSocket> Function(Uri url);

const int maxPairingRequestBytes = 64 * 1024;

class PairingRequestTooLargeException implements Exception {
  const PairingRequestTooLargeException();
}

class ConnectRelayRegistration {
  const ConnectRelayRegistration({
    required this.url,
    required this.endpointHost,
    required this.endpointPort,
  });

  final String url;
  final String endpointHost;
  final int endpointPort;
}

class ConnectAgent {
  ConnectAgent({
    required SshdPresenceProbe probe,
    required AuthorizedKeysFile keys,
    required PairingTokenGate gate,
    required PairingBind bind,
    required PairingCertificateProvider certificateProvider,
    required DateTime Function() now,
    required StableConnectHostId stableHostId,
    List<SshReachabilityEndpoint> extraEndpoints = const [],
    ConnectRelayRegistration? relayRegistration,
    PairedDeviceStore? deviceStore,
    GrantGenerator? generateGrant,
    RelaySocketSeam? relayConnectSocket,
  }) : _probe = probe,
       _keys = keys,
       _gate = gate,
       _bind = bind,
       _certificateProvider = certificateProvider,
       _now = now,
       _stableHostId = stableHostId,
       _extraEndpoints = List.unmodifiable(extraEndpoints),
       _relayRegistration = relayRegistration,
       _deviceStore = deviceStore,
       _generateGrant =
           generateGrant ??
           (() =>
               base64Url
                   .encode(
                     List<int>.generate(
                       32,
                       (_) => Random.secure().nextInt(256),
                     ),
                   )
                   .replaceAll('=', '')),
       _relayConnectSocket = relayConnectSocket;

  factory ConnectAgent.production({
    required AuthorizedKeysFile keys,
    required Filesystem fs,
    List<SshReachabilityEndpoint> extraEndpoints = const [],
    ConnectRelayRegistration? relayRegistration,
    SshdPresenceProbe? probe,
    PairingCertificateProvider? certificateProvider,
    PairedDeviceStore? deviceStore,
    RelaySocketSeam? relayConnectSocket,
  }) {
    return ConnectAgent(
      probe: probe ?? SshdPresence().probe,
      keys: keys,
      gate: PairingTokenGate(),
      bind: bindPairingHttps,
      certificateProvider: certificateProvider ?? ConnectTls(),
      now: DateTime.now,
      stableHostId: (appDataRoot) => ConnectSettingsStore(
        fs: fs,
        appDataRoot: appDataRoot,
      ).loadOrCreateHostId(),
      extraEndpoints: extraEndpoints,
      relayRegistration: relayRegistration,
      deviceStore: deviceStore,
      relayConnectSocket: relayConnectSocket,
    );
  }

  static const _inviteTtl = Duration(minutes: 10);

  final SshdPresenceProbe _probe;
  final AuthorizedKeysFile _keys;
  final PairingTokenGate _gate;
  final PairingBind _bind;
  final PairingCertificateProvider _certificateProvider;
  final DateTime Function() _now;
  final StableConnectHostId _stableHostId;
  List<SshReachabilityEndpoint> _extraEndpoints;
  ConnectRelayRegistration? _relayRegistration;
  final PairedDeviceStore? _deviceStore;
  final GrantGenerator _generateGrant;
  final RelaySocketSeam? _relayConnectSocket;
  final Lock _lifecycleLock = Lock();

  PairingBinding? _binding;
  StreamSubscription<PairingHttpRequest>? _requestSubscription;
  _QrSession? _session;
  SshPairingOffer? _currentOffer;
  ConnectRelayClient? _relayClient;

  /// Cached install id + sshd port for relay dial validation. These survive
  /// QR-session stops: an SSH grant stays usable while the app runs even when
  /// no QR is on screen.
  String? _cachedHostId;
  bool _relaySshdReachable = false;
  int? _relaySshdPort;

  SshPairingOffer? get currentOffer => _currentOffer;

  Future<void> startQrSession({
    required String advertiseAddress,
    required String username,
    required String displayName,
    required String appDataRoot,
  }) => _lifecycleLock.synchronized(
    () => _startQrSession(
      advertiseAddress: advertiseAddress,
      username: username,
      displayName: displayName,
      appDataRoot: appDataRoot,
    ),
  );

  Future<void> _startQrSession({
    required String advertiseAddress,
    required String username,
    required String displayName,
    required String appDataRoot,
  }) async {
    await _stopQrSession();
    final address = InternetAddress(advertiseAddress);
    if (_isWildcard(address)) {
      throw ArgumentError.value(
        advertiseAddress,
        'advertiseAddress',
        'must identify one LAN interface',
      );
    }

    final sshd = await _probe();
    final fingerprints = sshd.fingerprints
        .where((value) => value.startsWith('SHA256:'))
        .toSet()
        .toList(growable: false);
    // Keep relay SSH targets fresh with every QR-session probe.
    _relaySshdReachable = sshd.listening;
    _relaySshdPort = sshd.listening ? sshd.port : null;
    if (!sshd.listening || fingerprints.isEmpty) return;

    final certificate = await _certificateProvider.generate(
      appDataRoot: appDataRoot,
    );
    PairingBinding? binding;
    try {
      binding = await _bind(address, certificate.tlsContext);
      final session = _QrSession(
        advertiseAddress: advertiseAddress,
        username: username,
        displayName: displayName,
        appDataRoot: appDataRoot,
        hostId: await _stableHostId(appDataRoot),
        sshdPort: sshd.port,
        fingerprints: fingerprints,
        certificateSha256: certificate.sha256Hex,
        pairingPort: binding.port,
      );
      _cachedHostId = session.hostId;
      _binding = binding;
      _session = session;
      _currentOffer = _mintOffer(session);
      _requestSubscription = binding.requests.listen(_handleRequest);
    } on Object {
      _gate.invalidate();
      _currentOffer = null;
      _session = null;
      _binding = null;
      await binding?.close();
      rethrow;
    }
  }

  Future<void> stopQrSession() => _lifecycleLock.synchronized(_stopQrSession);

  Future<void> _stopQrSession() async {
    _gate.invalidate();
    _currentOffer = null;
    _session = null;
    final subscription = _requestSubscription;
    final binding = _binding;
    _requestSubscription = null;
    _binding = null;
    await subscription?.cancel();
    await binding?.close();
  }

  Future<void> regenerateQr() => _lifecycleLock.synchronized(_regenerateQr);

  /// App-lifetime relay registration. Unlike the QR session, the outbound
  /// register socket (and therefore off-LAN SSH via grants) stays up while
  /// Connect is enabled, independent of QR visibility.
  Future<void> enableRelay({
    required String appDataRoot,
    required ConnectRelayRegistration registration,
  }) => _lifecycleLock.synchronized(
    () => _enableRelay(appDataRoot: appDataRoot, registration: registration),
  );

  Future<void> _enableRelay({
    required String appDataRoot,
    required ConnectRelayRegistration registration,
  }) async {
    final hostId = await _stableHostId(appDataRoot);
    _cachedHostId = hostId;

    // One probe now: relay sshd targets refresh whenever a QR session runs.
    final sshd = await _probe();
    _relaySshdReachable = sshd.listening;
    _relaySshdPort = sshd.listening ? sshd.port : null;

    final client =
        _relayClient ??= ConnectRelayClient(
          validateDial: validateRelayDial,
          resolveTarget: resolveRelayTarget,
          connectSocket: _relayConnectSocket,
        );
    await client.start(url: Uri.parse(registration.url), hostId: hostId);

    final remintNeeded = _relayRegistration != registration;
    _relayRegistration = registration;
    if (_session != null && _binding != null && remintNeeded) {
      await _regenerateQr();
    }
  }

  /// Tears down the outbound register socket and drops the relay endpoint
  /// from any active offer. Grants already issued stay valid on disk; revoke
  /// is the explicit removal path.
  Future<void> disableRelay() =>
      _lifecycleLock.synchronized(() async {
        await _relayClient?.stop();
        _relayRegistration = null;
        if (_session != null && _binding != null) {
          await _regenerateQr();
        }
      });

  /// Credential gate for relay dials, owned by the agent because only it
  /// knows the live invite token and the grant registry. The relay itself
  /// never decides authorization.
  Future<bool> validateRelayDial(ConnectRelayDialRequest request) async {
    switch (request.channel) {
      case 'pair':
        final invite = request.inviteToken;
        if (invite == null || invite.isEmpty) return false;
        return _gate.matchesInvite(invite, now: _now());
      case 'ssh':
        final store = _deviceStore;
        final deviceId = request.deviceId;
        final grant = request.relayGrant;
        final hostId = _cachedHostId;
        if (store == null ||
            hostId == null ||
            deviceId == null ||
            deviceId.isEmpty ||
            grant == null ||
            grant.isEmpty) {
          return false;
        }
        return store.validateGrant(
          hostId: hostId,
          deviceId: deviceId,
          grant: grant,
        );
      default:
        return false;
    }
  }

  /// Loopback target for an accepted dial; null rejects without touching
  /// local services.
  Future<({InternetAddress host, int port})?> resolveRelayTarget(
    String channel,
  ) async {
    switch (channel) {
      case 'pair':
        // Only while the pairing HTTPS listener exists (QR surface visible).
        final binding = _binding;
        if (binding == null) return null;
        return (host: InternetAddress.loopbackIPv4, port: binding.port);
      case 'ssh':
        final port = _relaySshdPort;
        if (!_relaySshdReachable || port == null) return null;
        return (host: InternetAddress.loopbackIPv4, port: port);
      default:
        return null;
    }
  }

  Future<void> updateExtraEndpoints(
    List<SshReachabilityEndpoint> extraEndpoints,
  ) => _lifecycleLock.synchronized(() async {
    _extraEndpoints = List.unmodifiable(extraEndpoints);
    if (_session != null && _binding != null) {
      await _regenerateQr();
    }
  });

  Future<void> _regenerateQr() async {
    final session = _session;
    if (session == null || _binding == null) {
      throw StateError('No QR pairing session is active');
    }
    _gate.invalidate();
    _currentOffer = _mintOffer(session);
  }

  SshPairingOffer _mintOffer(_QrSession session) {
    final issuedAt = _now();
    final token = _gate.mint(now: issuedAt, ttl: _inviteTtl);
    final expiresAt = issuedAt.add(_inviteTtl).millisecondsSinceEpoch;
    final relay = _relayRegistration;
    return SshPairingOffer(
      v: 1,
      hostId: session.hostId,
      username: session.username,
      displayName: session.displayName,
      appDataRoot: session.appDataRoot,
      endpoints: [
        SshReachabilityEndpoint(
          kind: SshEndpointKind.lan,
          host: session.advertiseAddress,
          port: session.sshdPort,
        ),
        ..._extraEndpoints.where(
          (endpoint) => endpoint.kind == SshEndpointKind.extra,
        ),
        if (relay != null)
          SshReachabilityEndpoint(
            kind: SshEndpointKind.relay,
            host: relay.endpointHost,
            port: relay.endpointPort,
          ),
      ],
      hostKeyFingerprints: session.fingerprints,
      pairing: SshPairingSession(
        token: token,
        expiresAt: expiresAt,
        url: Uri(
          scheme: 'https',
          host: session.advertiseAddress,
          port: session.pairingPort,
          path: '/pair',
        ).toString(),
        tlsCertSha256: session.certificateSha256,
      ),
      relay: relay == null
          ? null
          : SshRelayOffer(
              v: 1,
              url: relay.url,
              hostId: session.hostId,
              inviteToken: token,
              inviteExpiresAt: expiresAt,
            ),
    );
  }

  Future<void> _handleRequest(PairingHttpRequest request) async {
    if (request.method != 'POST' || request.uri.path != '/pair') {
      await request.respond(
        statusCode: HttpStatus.notFound,
        body: const {'ok': false, 'error': 'notFound'},
      );
      return;
    }
    final body = request.body;
    final session = _session;
    if (body == null || session == null) {
      await request.respond(
        statusCode: HttpStatus.badRequest,
        body: const {'ok': false, 'error': 'invalid'},
      );
      return;
    }
    try {
      final result = await handlePairingPost(
        body: body,
        gate: _gate,
        keys: _keys,
        now: _now(),
        profileHint: session.displayName,
      );
      final relayGrant = await _issueRelayGrant(
        hostId: session.hostId,
        deviceId: body.deviceId,
      );
      await request.respond(
        statusCode: HttpStatus.ok,
        body: {
          'ok': result.ok,
          'profileHint': result.profileHint,
          if (result.relayGrant != null) 'relayGrant': result.relayGrant,
          if (relayGrant != null) 'relayGrant': relayGrant,
        },
      );
    } on PairingHttpException catch (error) {
      await request.respond(
        statusCode: HttpStatus.badRequest,
        body: {'ok': false, 'error': error.code},
      );
    } on Object {
      await request.respond(
        statusCode: HttpStatus.internalServerError,
        body: const {'ok': false, 'error': 'internal'},
      );
    }
  }

  /// Mints a long-lived device grant when a relay is registered. Only the
  /// SHA-256 digest is stored; the raw token travels to the phone in this
  /// response and never appears in logs or the QR.
  Future<String?> _issueRelayGrant({
    required String hostId,
    required String deviceId,
  }) async {
    final store = _deviceStore;
    if (store == null || _relayRegistration == null) return null;
    final grant = _generateGrant();
    await store.issueGrant(
      hostId: hostId,
      deviceId: deviceId,
      grant: grant,
    );
    return grant;
  }
}

class _QrSession {
  const _QrSession({
    required this.advertiseAddress,
    required this.username,
    required this.displayName,
    required this.appDataRoot,
    required this.hostId,
    required this.sshdPort,
    required this.fingerprints,
    required this.certificateSha256,
    required this.pairingPort,
  });

  final String advertiseAddress;
  final String username;
  final String displayName;
  final String appDataRoot;
  final String hostId;
  final int sshdPort;
  final List<String> fingerprints;
  final String certificateSha256;
  final int pairingPort;
}

bool _isWildcard(InternetAddress address) =>
    address.address == InternetAddress.anyIPv4.address ||
    address.address == InternetAddress.anyIPv6.address;

Future<PairingBinding> bindPairingHttps(
  InternetAddress address,
  Object tlsContext,
) async {
  if (tlsContext is! SecurityContext) {
    throw ArgumentError.value(
      tlsContext,
      'tlsContext',
      'must be a SecurityContext',
    );
  }
  final server = await HttpServer.bindSecure(address, 0, tlsContext);
  final requests = StreamController<PairingHttpRequest>();
  server.listen(
    (request) => _forwardHttpRequest(request, requests),
    onDone: requests.close,
  );
  return PairingBinding(
    address: server.address,
    port: server.port,
    close: () async {
      await server.close(force: true);
      if (!requests.isClosed) await requests.close();
    },
    requests: requests.stream,
  );
}

Future<void> _forwardHttpRequest(
  HttpRequest source,
  StreamController<PairingHttpRequest> destination,
) async {
  PairingPostBody? body;
  if (source.method == 'POST' && source.uri.path == '/pair') {
    try {
      body = await readPairingPostBody(
        source,
        contentLength: source.contentLength,
      );
    } on PairingRequestTooLargeException {
      source.response
        ..statusCode = HttpStatus.requestEntityTooLarge
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(const {'ok': false, 'error': 'tooLarge'}));
      await source.response.close();
      return;
    } on Object {
      body = null;
    }
  }
  if (destination.isClosed) {
    source.response.statusCode = HttpStatus.serviceUnavailable;
    await source.response.close();
    return;
  }
  destination.add(
    PairingHttpRequest(
      method: source.method,
      uri: source.uri,
      body: body,
      respond: ({required statusCode, required body}) async {
        source.response
          ..statusCode = statusCode
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(body));
        await source.response.close();
      },
    ),
  );
}

Future<PairingPostBody> readPairingPostBody(
  Stream<List<int>> source, {
  int? contentLength,
  int maxBytes = maxPairingRequestBytes,
}) async {
  if (maxBytes < 1) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'must be positive');
  }
  if (contentLength != null && contentLength > maxBytes) {
    throw const PairingRequestTooLargeException();
  }

  final bytes = BytesBuilder(copy: false);
  var byteCount = 0;
  await for (final chunk in source) {
    byteCount += chunk.length;
    if (byteCount > maxBytes) {
      throw const PairingRequestTooLargeException();
    }
    bytes.add(chunk);
  }

  final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
  if (decoded is! Map) throw const FormatException();
  final json = decoded.cast<String, Object?>();
  return PairingPostBody(
    token: json['token'] as String,
    deviceId: json['deviceId'] as String,
    deviceName: json['deviceName'] as String,
    publicKey: json['publicKey'] as String,
  );
}
