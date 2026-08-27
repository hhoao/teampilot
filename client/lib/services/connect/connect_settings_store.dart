import 'dart:convert';
import 'dart:math';

import '../../models/ssh_reachability.dart';
import '../io/filesystem.dart';

typedef ConnectHostIdGenerator = String Function();

class ConnectSettings {
  const ConnectSettings({
    required this.hostId,
    this.extraEndpoints = const [],
    this.relayUrl = '',
  });

  final String hostId;
  final List<SshReachabilityEndpoint> extraEndpoints;
  final String relayUrl;
}

class ConnectSettingsStore {
  ConnectSettingsStore({
    required this.fs,
    required this.appDataRoot,
    ConnectHostIdGenerator? generateHostId,
  }) : _generateHostId = generateHostId ?? _randomHostId;

  final Filesystem fs;
  final String appDataRoot;
  final ConnectHostIdGenerator _generateHostId;

  String get settingsPath =>
      fs.pathContext.join(appDataRoot, 'connect', 'settings.json');

  Future<String> loadOrCreateHostId() async {
    final json = await _readJson();
    final existing = _hostIdFrom(json);
    if (existing != null) return existing;

    final hostId = _generateHostId();
    if (!_isHostId(hostId)) {
      throw StateError('Connect host ID generator returned an invalid value');
    }
    await _write({...json, 'hostId': hostId});
    return hostId;
  }

  Future<ConnectSettings> load() async {
    final hostId = await loadOrCreateHostId();
    final json = await _readJson();
    final endpoints = <SshReachabilityEndpoint>[];
    final rawEndpoints = json['extraEndpoints'];
    if (rawEndpoints is List) {
      for (final raw in rawEndpoints) {
        if (raw is! Map) continue;
        final endpoint = SshReachabilityEndpoint.tryParse(
          raw.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (endpoint?.kind == SshEndpointKind.extra) {
          endpoints.add(endpoint!);
        }
      }
    }
    return ConnectSettings(
      hostId: hostId,
      extraEndpoints: List.unmodifiable(endpoints),
      relayUrl: json['relayUrl'] is String ? json['relayUrl'] as String : '',
    );
  }

  Future<void> save({
    required List<SshReachabilityEndpoint> extraEndpoints,
    required String relayUrl,
  }) async {
    final hostId = await loadOrCreateHostId();
    final endpoints = extraEndpoints
        .where((endpoint) => endpoint.kind == SshEndpointKind.extra)
        .toList(growable: false);
    await _write({
      'hostId': hostId,
      'extraEndpoints': endpoints.map((endpoint) => endpoint.toJson()).toList(),
      'relayUrl': relayUrl.trim(),
    });
  }

  Future<Map<String, Object?>> _readJson() async {
    final contents = await fs.readString(settingsPath);
    if (contents == null || contents.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(contents);
      if (decoded is! Map) return {};
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } on FormatException {
      return {};
    }
  }

  String? _hostIdFrom(Map<String, Object?> json) {
    final hostId = json['hostId'];
    return hostId is String && _isHostId(hostId) ? hostId : null;
  }

  Future<void> _write(Map<String, Object?> json) async {
    await fs.ensureDir(fs.pathContext.dirname(settingsPath));
    await fs.atomicWrite(settingsPath, jsonEncode(json));
  }

  static String _randomHostId() {
    final random = Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static bool _isHostId(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{16}$').hasMatch(value);
}
