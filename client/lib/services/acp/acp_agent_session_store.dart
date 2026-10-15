import 'dart:convert';

import '../io/filesystem.dart';

/// Sidecar persistence for one ACP session's agent-side `sessionId`.
///
/// The id is the ACP `session/new` response id, used to `session/load` the
/// same agent session on a later start. File shape: `{"v":1,"sessionId":"…"}`.
class AcpAgentSessionStore {
  AcpAgentSessionStore({required Filesystem fs, required this.path}) : _fs = fs;

  final Filesystem _fs;
  final String path;

  Future<String?> read() async {
    final raw = await _fs.readString(path);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['v'] != 1) return null;
      final id = decoded['sessionId'];
      return (id is String && id.isNotEmpty) ? id : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> write(String sessionId) =>
      _fs.atomicWrite(path, jsonEncode({'v': 1, 'sessionId': sessionId}));

  Future<void> clear() => _fs.atomicWrite(path, '');
}
