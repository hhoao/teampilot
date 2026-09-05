import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  /// Uncompressed base64 JSON for copy/paste links.
  String get bareCode =>
      base64Url.encode(utf8.encode(jsonEncode(toJson()))).replaceAll('=', '');

  /// Gzip-compressed compact offer for QR rendering (prefix `z`). Self-contained;
  /// the phone does not fetch anything after scan.
  String get qrPayload {
    final compressed = gzip.encode(utf8.encode(jsonEncode(_toQrJson())));
    return 'z${base64Url.encode(compressed).replaceAll('=', '')}';
  }

  /// Binary QR payload: `0x7A` marker + raw-deflate of the compact JSON.
  ///
  /// Raw bytes (no base64 layer) keep the QR module grid coarse — the string
  /// form above inflates ~1.33x inside the QR's byte mode.
  List<int> get qrBytes => [
    _binaryMarker,
    ...ZLibEncoder(raw: true).convert(
      utf8.encode(jsonEncode(_toCompactQrJson())),
    ),
  ];

  static const int _binaryMarker = 0x7A;

  String encode() => 'teampilot://pair-ssh?code=$bareCode';

  /// Omits reconstructable fields to keep the QR module grid coarser.
  Map<String, Object?> _toQrJson() {
    final pairingUri = Uri.parse(pairing.url);
    return {
      'v': v,
      'hostId': hostId,
      'username': username,
      'appDataRoot': appDataRoot,
      'endpoints': endpoints.map((endpoint) => endpoint.toJson()).toList(),
      'hostKeyFingerprints': hostKeyFingerprints,
      'pairing': {
        'token': pairing.token,
        'tlsCertSha256': pairing.tlsCertSha256,
        'port': pairingUri.port,
      },
      if (relay != null) 'relay': {'url': relay!.url},
    };
  }

  /// Short-key variant of [_toQrJson]; every saved byte coarsens the QR grid.
  Map<String, Object?> _toCompactQrJson() {
    return {
      'v': v,
      'h': hostId,
      'u': username,
      'a': appDataRoot,
      'e': endpoints
          .map(
            (endpoint) => {
              'k': _endpointKindCode(endpoint.kind),
              'h': endpoint.host,
              'p': endpoint.port,
            },
          )
          .toList(),
      'f': hostKeyFingerprints.map(_stripFingerprintPrefix).toList(),
      'g': {
        't': pairing.token,
        'c': _compactCertPin(pairing.tlsCertSha256),
        'p': Uri.parse(pairing.url).port,
      },
      if (relay != null) 'r': {'u': relay!.url},
    };
  }

  static String _endpointKindCode(SshEndpointKind kind) => switch (kind) {
    SshEndpointKind.lan => 'l',
    SshEndpointKind.extra => 'x',
    SshEndpointKind.relay => 'r',
  };

  static SshEndpointKind? _endpointKindFromCode(String code) => switch (code) {
    'l' => SshEndpointKind.lan,
    'x' => SshEndpointKind.extra,
    'r' => SshEndpointKind.relay,
    _ => null,
  };

  /// `SHA256:<body>` → `<body>`; the prefix is re-added when decoding.
  static String _stripFingerprintPrefix(String fingerprint) => fingerprint
      .startsWith('SHA256:')
      ? fingerprint.substring('SHA256:'.length)
      : fingerprint;

  /// A 64-char hex pin becomes base64url of the raw bytes (43 chars);
  /// anything else (test fixtures) is kept verbatim.
  static String _compactCertPin(String pin) {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(pin)) return pin;
    return base64Url.encode(_hexDecode(pin)).replaceAll('=', '');
  }

  static String _expandCertPin(String value) {
    // base64url of 32 bytes is exactly 43 chars without padding.
    if (value.length != 43) return value;
    try {
      final padded = value.padRight((value.length + 3) ~/ 4 * 4, '=');
      return _hexEncode(base64Url.decode(padded));
    } on Object {
      return value;
    }
  }

  /// Expands the short-key compact form into the full-key JSON understood by
  /// [fromJson]. Detected by `h` presence; full-key offers pass through.
  static Map<String, Object?> _expandCompactQrJson(Map<String, Object?> json) {
    if (json['h'] == null || json['hostId'] != null) return json;
    final endpoints =
        (json['e'] as List?)
            ?.whereType<Map>()
            .map((entry) {
              final endpoint = entry.cast<String, Object?>();
              return {
                'kind': _endpointKindFromCode(endpoint['k'] as String? ?? '')
                    ?.name,
                'host': endpoint['h'],
                'port': endpoint['p'],
              };
            })
            .where((endpoint) => endpoint['kind'] != null)
            .toList();
    Map<String, Object?> pairing = const {};
    final pairingRaw = json['g'];
    if (pairingRaw is Map) {
      final compact = Map<String, Object?>.from(
        pairingRaw.cast<String, Object?>(),
      );
      pairing = {
        'token': compact['t'],
        'tlsCertSha256': _expandCertPin(compact['c'] as String? ?? ''),
        'port': compact['p'],
      };
    }
    final relayRaw = json['r'];
    return {
      'v': json['v'],
      'hostId': json['h'],
      'username': json['u'],
      'appDataRoot': json['a'],
      'endpoints': endpoints,
      'hostKeyFingerprints':
          (json['f'] as List?)
              ?.whereType<String>()
              .map((body) => 'SHA256:$body')
              .toList(),
      'pairing': pairing,
      if (relayRaw is Map) 'relay': {'url': relayRaw['u']},
    };
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
    final code = _extractCode(input);
    if (code == null || code.isEmpty) {
      throw const SshPairingOfferFormatException('missing pairing code');
    }
    try {
      if (code.startsWith('r')) {
        // Binary QR payload relayed as base64url text by the scanner page.
        return decodeBytes(
          Uint8List.fromList(_base64UrlDecodeBytes(code.substring(1))),
        );
      }
      final decoded = _decodeCodePayload(code);
      return SshPairingOffer.fromJson(_normalizeDecodedJson(decoded));
    } on SshPairingOfferFormatException {
      rethrow;
    } on Object {
      throw const SshPairingOfferFormatException('invalid pairing code');
    }
  }

  /// Decodes raw QR content bytes: either the binary compact form from
  /// [qrBytes] (marker + raw deflate), or any text payload (legacy `z` code,
  /// bare code, deep link) encoded as UTF-8.
  static SshPairingOffer decodeBytes(Uint8List bytes) {
    if (bytes.isNotEmpty && bytes.first == _binaryMarker) {
      try {
        final jsonText = utf8.decode(
          ZLibDecoder(raw: true).convert(bytes.sublist(1)),
        );
        final decoded = jsonDecode(jsonText);
        if (decoded is! Map) {
          throw const SshPairingOfferFormatException('offer must be an object');
        }
        return SshPairingOffer.fromJson(
          _normalizeDecodedJson(_expandCompactQrJson(decoded.cast<String, Object?>())),
        );
      } on SshPairingOfferFormatException {
        rethrow;
      } on Object {
        // Not a binary payload after all — fall through to the text path.
      }
    }
    try {
      return decode(utf8.decode(bytes));
    } on Object {
      throw const SshPairingOfferFormatException('invalid pairing code');
    }
  }

  static List<int> _base64UrlDecodeBytes(String value) {
    final padded = value.padRight((value.length + 3) ~/ 4 * 4, '=');
    return base64Url.decode(padded);
  }

  static String? _extractCode(String input) {
    final trimmed = input.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri?.scheme == 'teampilot' && uri?.host == 'pair-ssh') {
      return uri?.queryParameters['code'];
    }
    return trimmed;
  }

  static Map<String, Object?> _decodeCodePayload(String code) {
    if (code.startsWith('z')) {
      final payload = code.substring(1);
      final padded = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');
      final bytes = base64Url.decode(padded);
      final jsonText = utf8.decode(gzip.decode(bytes));
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) {
        throw const SshPairingOfferFormatException('offer must be an object');
      }
      return decoded.cast<String, Object?>();
    }
    final padded = code.padRight((code.length + 3) ~/ 4 * 4, '=');
    final decoded = jsonDecode(utf8.decode(base64Url.decode(padded)));
    if (decoded is! Map) {
      throw const SshPairingOfferFormatException('offer must be an object');
    }
    return decoded.cast<String, Object?>();
  }

  static Map<String, Object?> _normalizeDecodedJson(Map<String, Object?> json) {
    final pairingRaw = json['pairing'];
    if (pairingRaw is Map) {
      final pairing = Map<String, Object?>.from(
        pairingRaw.cast<String, Object?>(),
      );
      if (pairing['url'] == null) {
        final port = (pairing.remove('port') as num?)?.toInt() ?? 2768;
        final host = _lanHost(json);
        pairing['url'] = 'https://$host:$port/pair';
      }
      pairing.putIfAbsent('expiresAt', () => 1);
      json['pairing'] = pairing;
    }
    json.putIfAbsent('displayName', () => json['username']);
    final relayRaw = json['relay'];
    if (relayRaw is Map) {
      final pairing = (json['pairing'] as Map).cast<String, Object?>();
      final relay = Map<String, Object?>.from(relayRaw.cast<String, Object?>());
      relay.putIfAbsent('v', () => 1);
      relay.putIfAbsent('hostId', () => json['hostId']);
      relay.putIfAbsent('inviteToken', () => pairing['token']);
      relay.putIfAbsent('inviteExpiresAt', () => pairing['expiresAt']);
      json['relay'] = relay;
    }
    return json;
  }

  static String _lanHost(Map<String, Object?> json) {
    final endpoints = json['endpoints'];
    if (endpoints is List) {
      for (final entry in endpoints) {
        if (entry is! Map) continue;
        final endpoint = entry.cast<String, Object?>();
        if (endpoint['kind'] == 'lan') {
          final host = endpoint['host'] as String?;
          if (host != null && host.trim().isNotEmpty) {
            return host;
          }
        }
      }
    }
    throw const SshPairingOfferFormatException('missing endpoints');
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

List<int> _hexDecode(String hex) => [
  for (var i = 0; i + 1 < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

String _hexEncode(List<int> bytes) => bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();
