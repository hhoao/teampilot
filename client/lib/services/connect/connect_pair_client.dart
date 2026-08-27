import 'dart:convert';
import 'dart:io';

import 'pairing_http.dart';
import 'ssh_pairing_offer.dart';

/// Upper bound for the pairing HTTPS POST (connect + response body).
const Duration pairingPostTimeout = Duration(seconds: 15);

abstract interface class PairingPostTransport {
  Future<PairingPostResult> post({
    required Uri url,
    required Map<String, Object?> body,
    required String tlsCertSha256,
  });
}

class ConnectPairClient {
  ConnectPairClient({
    PairingPostTransport? transport,
    Duration pairingTimeout = pairingPostTimeout,
  }) : _transport =
           transport ?? _PinnedPairingTransport(timeout: pairingTimeout);

  final PairingPostTransport _transport;

  Future<PairingPostResult> pair({
    required SshPairingOffer offer,
    required String deviceId,
    required String deviceName,
    required String publicKey,
  }) async {
    final url = Uri.tryParse(offer.pairing.url);
    if (url == null || url.scheme != 'https' || url.host.isEmpty) {
      throw const ConnectPairClientException('invalidUrl');
    }
    return pairAt(
      url: url,
      tlsCertSha256: offer.pairing.tlsCertSha256,
      body: {
        'token': offer.pairing.token,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'publicKey': publicKey,
      },
    );
  }

  /// POSTs a pairing body to [url] trusting only [tlsCertSha256]. Used for
  /// the direct LAN POST and for the relay pair channel's loopback POST.
  Future<PairingPostResult> pairAt({
    required Uri url,
    required Map<String, Object?> body,
    required String tlsCertSha256,
  }) {
    return _transport.post(url: url, body: body, tlsCertSha256: tlsCertSha256);
  }
}

/// Performs pinned HTTPS pairing GET/POST against the desktop listener.
class _PinnedPairingTransport implements PairingPostTransport {
  const _PinnedPairingTransport({this.timeout = pairingPostTimeout});

  final Duration timeout;

  @override
  Future<PairingPostResult> post({
    required Uri url,
    required Map<String, Object?> body,
    required String tlsCertSha256,
  }) async {
    final context = SecurityContext(withTrustedRoots: false);
    final client = HttpClient(context: context)
      ..connectionTimeout = timeout
      ..badCertificateCallback = (certificate, _, __) {
        return PairingTlsPin.matches(
          derBytes: certificate.der,
          expectedSha256Hex: tlsCertSha256,
        );
      };
    try {
      return await _postPinned(
        client: client,
        url: url,
        body: body,
        tlsCertSha256: tlsCertSha256,
      ).timeout(
        timeout,
        onTimeout: () => throw const ConnectPairClientException('timeout'),
      );
    } on FormatException {
      throw const ConnectPairClientException('invalidResponse');
    } finally {
      client.close(force: true);
    }
  }

  Future<PairingPostResult> _postPinned({
    required HttpClient client,
    required Uri url,
    required Map<String, Object?> body,
    required String tlsCertSha256,
  }) async {
    // With no trust roots, this callback runs during the TLS handshake.
    // Therefore the request body (which contains the one-time token) is not
    // sent until the advertised DER certificate hash matches.
    final request = await client.postUrl(url);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final certificate = response.certificate;
    if (certificate == null ||
        !PairingTlsPin.matches(
          derBytes: certificate.der,
          expectedSha256Hex: tlsCertSha256,
        )) {
      throw const ConnectPairClientException('tlsPinMismatch');
    }
    final raw = await utf8.decoder.bind(response).join();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const ConnectPairClientException('invalidResponse');
    }
    final json = decoded.cast<String, Object?>();
    final ok = json['ok'] == true;
    if (!ok) {
      throw PairingHttpException(json['error'] as String? ?? 'invalid');
    }
    final profileHint = json['profileHint'] as String?;
    if (profileHint == null || profileHint.trim().isEmpty) {
      throw const ConnectPairClientException('invalidResponse');
    }
    return PairingPostResult(
      ok: true,
      profileHint: profileHint,
      relayGrant: json['relayGrant'] as String?,
    );
  }
}

class ConnectPairClientException implements Exception {
  const ConnectPairClientException(this.code);

  final String code;

  @override
  String toString() => 'ConnectPairClientException($code)';
}
