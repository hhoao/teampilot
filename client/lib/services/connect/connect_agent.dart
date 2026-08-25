import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/ssh_reachability.dart';
import '../io/filesystem.dart';
import 'authorized_keys_file.dart';
import 'connect_settings_store.dart';
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
  }) : _probe = probe,
       _keys = keys,
       _gate = gate,
       _bind = bind,
       _certificateProvider = certificateProvider,
       _now = now,
       _stableHostId = stableHostId,
       _extraEndpoints = List.unmodifiable(extraEndpoints),
       _relayRegistration = relayRegistration;

  factory ConnectAgent.production({
    required AuthorizedKeysFile keys,
    required Filesystem fs,
    List<SshReachabilityEndpoint> extraEndpoints = const [],
    ConnectRelayRegistration? relayRegistration,
    SshdPresenceProbe? probe,
    PairingCertificateProvider? certificateProvider,
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
  final List<SshReachabilityEndpoint> _extraEndpoints;
  final ConnectRelayRegistration? _relayRegistration;

  PairingBinding? _binding;
  StreamSubscription<PairingHttpRequest>? _requestSubscription;
  _QrSession? _session;
  SshPairingOffer? _currentOffer;

  SshPairingOffer? get currentOffer => _currentOffer;

  Future<void> startQrSession({
    required String advertiseAddress,
    required String username,
    required String displayName,
    required String appDataRoot,
  }) async {
    await stopQrSession();
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

  Future<void> stopQrSession() async {
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

  Future<void> regenerateQr() async {
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
      await request.respond(
        statusCode: HttpStatus.ok,
        body: {
          'ok': result.ok,
          'profileHint': result.profileHint,
          if (result.relayGrant != null) 'relayGrant': result.relayGrant,
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
      final text = await utf8.decoder.bind(source).join();
      if (text.length > 64 * 1024) throw const FormatException();
      final decoded = jsonDecode(text);
      if (decoded is! Map) throw const FormatException();
      final json = decoded.cast<String, Object?>();
      body = PairingPostBody(
        token: json['token'] as String,
        deviceId: json['deviceId'] as String,
        deviceName: json['deviceName'] as String,
        publicKey: json['publicKey'] as String,
      );
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
