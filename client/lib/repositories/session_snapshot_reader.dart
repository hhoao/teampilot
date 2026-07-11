import 'dart:convert';
import 'dart:io';

/// Scans a workspace's `sessions/` directory and decodes every `session.json`.
///
/// Runs on the calling isolate. A prior `Isolate.run` path hung on Linux debug
/// cold start (child isolate never resumed) and left the boot splash stuck;
/// session payloads are small enough that sync decode is fine for boot and
/// tab switches.
///
/// Native (local disk) only — the SFTP/WSL filesystems hold non-sendable
/// handles, so callers fall back to the [Filesystem] abstraction for those.
abstract final class SessionSnapshotReader {
  SessionSnapshotReader._();

  static const sessionFileName = 'session.json';

  static Future<List<Map<String, Object?>>> readSessionMaps(
    String sessionsDir,
  ) async {
    return _readSessionMaps(sessionsDir);
  }

  /// Same parse as [readSessionMaps], for callers that need a sync entry point.
  static List<Map<String, Object?>> readSessionMapsSync(String sessionsDir) =>
      _readSessionMaps(sessionsDir);
}

List<Map<String, Object?>> _readSessionMaps(String sessionsDir) {
  final dir = Directory(sessionsDir);
  if (!dir.existsSync()) return const [];
  final out = <Map<String, Object?>>[];
  for (final entry in dir.listSync(followLinks: false)) {
    if (entry is! Directory) continue;
    final filePath = entry.uri
        .resolve(SessionSnapshotReader.sessionFileName)
        .toFilePath();
    final file = File(filePath);
    if (!file.existsSync()) continue;
    try {
      final raw = file.readAsStringSync();
      if (raw.isEmpty) continue;
      final decoded = jsonDecode(raw);
      if (decoded is Map) out.add(Map<String, Object?>.from(decoded));
    } on Object {
      // Skip unreadable/corrupt session files; best-effort listing.
      continue;
    }
  }
  return out;
}
