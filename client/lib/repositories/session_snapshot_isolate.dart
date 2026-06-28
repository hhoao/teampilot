import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// Scans a workspace's `sessions/` directory and decodes every `session.json`
/// off the UI isolate.
///
/// Reading + `jsonDecode` for a workspace with many (and large) session files
/// is enough CPU work to stall the UI thread — freezing the whole app and even
/// the loading skeleton — when done inline. Doing the directory walk, file
/// reads, and decode in one [Isolate.run] keeps the UI isolate free; the cheap
/// `AppSession.fromJson` over plain maps then runs back on the main isolate.
///
/// Native (local disk) only — the SFTP/WSL filesystems hold non-sendable
/// handles, so callers fall back to the [Filesystem] abstraction for those.
abstract final class SessionSnapshotIsolate {
  SessionSnapshotIsolate._();

  static const sessionFileName = 'session.json';

  static Future<List<Map<String, Object?>>> readSessionMaps(String sessionsDir) {
    return Isolate.run(() => _readSessionMaps(sessionsDir));
  }
}

List<Map<String, Object?>> _readSessionMaps(String sessionsDir) {
  final dir = Directory(sessionsDir);
  if (!dir.existsSync()) return const [];
  final out = <Map<String, Object?>>[];
  for (final entry in dir.listSync(followLinks: false)) {
    if (entry is! Directory) continue;
    final filePath = entry.uri
        .resolve(SessionSnapshotIsolate.sessionFileName)
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
