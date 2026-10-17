import 'dart:convert';

import '../io/filesystem.dart';

/// One persisted agent-side ACP session identity.
///
/// [cwd] is the directory the agent session was opened in. `session/load`
/// requires the same directory (OpenCode rejects a mismatch with
/// `ACPSessionDirectoryMismatchError`), so it is persisted next to the id.
class AcpAgentSessionRecord {
  const AcpAgentSessionRecord({required this.sessionId, this.cwd});

  final String sessionId;

  /// The ACP `cwd` the session was opened with, or null for sidecars written
  /// before the directory was recorded.
  final String? cwd;
}

/// Sidecar persistence for one ACP session's agent-side `sessionId` and the
/// working directory it lives in.
///
/// The id is the ACP `session/new` response id, used to `session/load` the
/// same agent session on a later start. File shape:
/// `{"v":1,"sessionId":"…","cwd":"…"}`. Older files without `cwd` still parse;
/// resume then falls back to the caller's working directory.
class AcpAgentSessionStore {
  AcpAgentSessionStore({required Filesystem fs, required this.path}) : _fs = fs;

  final Filesystem _fs;
  final String path;

  Future<AcpAgentSessionRecord?> readRecord() async {
    final raw = await _fs.readString(path);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['v'] != 1) return null;
      final id = decoded['sessionId'];
      if (id is! String || id.isEmpty) return null;
      final cwd = decoded['cwd'];
      return AcpAgentSessionRecord(
        sessionId: id,
        cwd: (cwd is String && cwd.trim().isNotEmpty) ? cwd.trim() : null,
      );
    } on FormatException {
      return null;
    }
  }

  /// The stored agent session id, or null when absent/unreadable.
  Future<String?> read() async => (await readRecord())?.sessionId;

  Future<void> write(String sessionId, {String? cwd}) {
    final normalized = cwd?.trim() ?? '';
    return _fs.atomicWrite(
      path,
      jsonEncode({
        'v': 1,
        'sessionId': sessionId,
        if (normalized.isNotEmpty) 'cwd': normalized,
      }),
    );
  }

  Future<void> clear() => _fs.atomicWrite(path, '');
}
