import 'dart:convert';

import '../../models/ssh_reachability.dart';

class SshPairingOfferFormatException implements Exception {
  const SshPairingOfferFormatException(this.message);

  final String message;

  @override
  String toString() => 'SshPairingOfferFormatException: $message';
}

class SshPairingSession {
  const SshPairingSession({
    required this.token,
    required this.expiresAt,
    required this.url,
    required this.tlsCertSha256,
  });

  final String token;
  final int expiresAt;
  final String url;
  final String tlsCertSha256;

  Map<String, Object?> toJson() => {
    'token': token,
    'expiresAt': expiresAt,
    'url': url,
    'tlsCertSha256': tlsCertSha256,
  };

  factory SshPairingSession.fromJson(Map<String, Object?> json) {
    final token = _requiredString(json, 'token');
    final url = _requiredString(json, 'url');
    final pin = _requiredString(json, 'tlsCertSha256');
    final expiresAt = (json['expiresAt'] as num?)?.toInt();
    if (expiresAt == null || expiresAt <= 0) {
      throw const SshPairingOfferFormatException('invalid pairing expiry');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const SshPairingOfferFormatException('invalid pairing URL');
    }
    return SshPairingSession(
      token: token,
      expiresAt: expiresAt,
      url: url,
      tlsCertSha256: pin,
    );
  }
}

class SshRelayOffer {
  const SshRelayOffer({
    required this.v,
    required this.url,
    required this.hostId,
    required this.inviteToken,
    required this.inviteExpiresAt,
  });

  final int v;
  final String url;
  final String hostId;
  final String inviteToken;
  final int inviteExpiresAt;

  Map<String, Object?> toJson() => {
    'v': v,
    'url': url,
    'hostId': hostId,
    'inviteToken': inviteToken,
    'inviteExpiresAt': inviteExpiresAt,
  };

  factory SshRelayOffer.fromJson(Map<String, Object?> json) {
    if ((json['v'] as num?)?.toInt() != 1) {
      throw const SshPairingOfferFormatException('unsupported relay version');
    }
    final url = _requiredString(json, 'url');
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'ws' && uri.scheme != 'wss')) {
      throw const SshPairingOfferFormatException('invalid relay URL');
    }
    return SshRelayOffer(
      v: 1,
      url: url,
      hostId: _hostId(_requiredString(json, 'hostId')),
      inviteToken: _requiredString(json, 'inviteToken'),
      inviteExpiresAt: _requiredPositiveInt(json, 'inviteExpiresAt'),
    );
  }
}

class SshPairingOffer {
  const SshPairingOffer({
    required this.v,
    required this.hostId,
    required this.username,
    required this.displayName,
    required this.appDataRoot,
    required this.endpoints,
    required this.hostKeyFingerprints,
    required this.pairing,
    this.relay,
  });

  final int v;
  final String hostId;
  final String username;
  final String displayName;
  final String appDataRoot;
  final List<SshReachabilityEndpoint> endpoints;
  final List<String> hostKeyFingerprints;
  final SshPairingSession pairing;
  final SshRelayOffer? relay;

  String encode() {
    final code = base64Url
        .encode(utf8.encode(jsonEncode(toJson())))
        .replaceAll('=', '');
    return 'teampilot://pair-ssh?code=$code';
  }

  Map<String, Object?> toJson() => {
    'v': v,
    'hostId': hostId,
    'username': username,
    'displayName': displayName,
    'appDataRoot': appDataRoot,
    'endpoints': endpoints.map((endpoint) => endpoint.toJson()).toList(),
    'hostKeyFingerprints': hostKeyFingerprints,
    'pairing': pairing.toJson(),
    if (relay != null) 'relay': relay!.toJson(),
  };

  static SshPairingOffer decode(String input) {
    final trimmed = input.trim();
    final uri = Uri.tryParse(trimmed);
    final code = uri?.scheme == 'teampilot' && uri?.host == 'pair-ssh'
        ? uri?.queryParameters['code']
        : trimmed;
    if (code == null || code.isEmpty) {
      throw const SshPairingOfferFormatException('missing pairing code');
    }
    try {
      final padded = code.padRight((code.length + 3) ~/ 4 * 4, '=');
      final decoded = jsonDecode(utf8.decode(base64Url.decode(padded)));
      if (decoded is! Map) {
        throw const SshPairingOfferFormatException('offer must be an object');
      }
      return SshPairingOffer.fromJson(decoded.cast<String, Object?>());
    } on SshPairingOfferFormatException {
      rethrow;
    } on Object {
      throw const SshPairingOfferFormatException('invalid pairing code');
    }
  }

  factory SshPairingOffer.fromJson(Map<String, Object?> json) {
    if ((json['v'] as num?)?.toInt() != 1) {
      throw const SshPairingOfferFormatException('unsupported offer version');
    }
    final endpointJson = json['endpoints'];
    if (endpointJson is! List) {
      throw const SshPairingOfferFormatException('missing endpoints');
    }
    final endpoints = endpointJson
        .whereType<Map>()
        .map(
          (value) =>
              SshReachabilityEndpoint.tryParse(value.cast<String, Object?>()),
        )
        .whereType<SshReachabilityEndpoint>()
        .toList(growable: false);
    final pairingJson = json['pairing'];
    if (pairingJson is! Map) {
      throw const SshPairingOfferFormatException('missing pairing session');
    }
    final relayRaw = json['relay'];
    if (relayRaw != null && relayRaw is! Map) {
      throw const SshPairingOfferFormatException('invalid relay offer');
    }
    final fingerprints =
        (json['hostKeyFingerprints'] as List?)
            ?.whereType<String>()
            .where((value) => value.startsWith('SHA256:'))
            .toList(growable: false) ??
        const <String>[];
    return SshPairingOffer(
      v: 1,
      hostId: _hostId(_requiredString(json, 'hostId')),
      username: _requiredString(json, 'username'),
      displayName: _requiredString(json, 'displayName'),
      appDataRoot: _requiredString(json, 'appDataRoot'),
      endpoints: endpoints,
      hostKeyFingerprints: fingerprints,
      pairing: SshPairingSession.fromJson(pairingJson.cast<String, Object?>()),
      relay: relayRaw == null
          ? null
          : SshRelayOffer.fromJson((relayRaw as Map).cast<String, Object?>()),
    );
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key] as String?;
  if (value == null || value.trim().isEmpty) {
    throw SshPairingOfferFormatException('missing $key');
  }
  return value;
}

int _requiredPositiveInt(Map<String, Object?> json, String key) {
  final value = (json[key] as num?)?.toInt();
  if (value == null || value <= 0) {
    throw SshPairingOfferFormatException('invalid $key');
  }
  return value;
}

String _hostId(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]{16}$').hasMatch(value)) {
    throw const SshPairingOfferFormatException('invalid hostId');
  }
  return value;
}
