import 'dart:convert';
import 'dart:math';

import '../io/filesystem.dart';

typedef ConnectHostIdGenerator = String Function();

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
    final existing = await _readHostId();
    if (existing != null) return existing;

    final hostId = _generateHostId();
    if (!_isHostId(hostId)) {
      throw StateError('Connect host ID generator returned an invalid value');
    }
    await fs.ensureDir(fs.pathContext.dirname(settingsPath));
    await fs.atomicWrite(settingsPath, jsonEncode({'hostId': hostId}));
    return hostId;
  }

  Future<String?> _readHostId() async {
    final contents = await fs.readString(settingsPath);
    if (contents == null || contents.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(contents);
      if (decoded is! Map) return null;
      final hostId = decoded['hostId'];
      return hostId is String && _isHostId(hostId) ? hostId : null;
    } on FormatException {
      return null;
    }
  }

  static String _randomHostId() {
    final random = Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static bool _isHostId(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{16}$').hasMatch(value);
}
