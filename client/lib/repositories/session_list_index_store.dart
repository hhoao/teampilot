import 'dart:convert';

import 'package:synchronized/synchronized.dart';

import '../models/session_list_entry.dart';
import '../services/storage/storage_failure.dart';
import 'session_repository_fs.dart';

/// Derived sidebar snapshot for one workspace's sessions.
///
/// Each [session.json] remains source of truth; this file is updated on
/// repository mutations so the conversation list can load one JSON instead of
/// every session document.
class SessionListIndexStore {
  SessionListIndexStore(this._fs, this._workspaceId);

  final SessionRepositoryFs _fs;
  final String _workspaceId;

  /// Serializes read-modify-write so concurrent upserts do not drop entries.
  static final _mutationLocks = <String, Lock>{};

  static const indexVersion = 1;

  String get _indexFile => _fs.layout.sessionsIndexFile(_workspaceId);

  Lock get _mutationLock => _mutationLocks.putIfAbsent(_indexFile, Lock.new);

  /// Reads the derived index. Missing, corrupt, or unknown-version files
  /// return `null` so callers can rebuild. Transport failures are rethrown.
  Future<List<SessionListEntry>?> tryRead() async {
    final raw = await _fs.readText(_indexFile);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      if (decoded['version'] != indexVersion) return null;
      final list = decoded['sessions'];
      if (list is! List) return null;
      return [
        for (final item in list)
          if (item is Map)
            SessionListEntry.fromJson(Map<String, Object?>.from(item)),
      ];
    } on Object catch (error) {
      if (isStorageTransportFailure(error)) rethrow;
      return null;
    }
  }

  Future<void> writeAll(List<SessionListEntry> sessions) {
    return _mutationLock.synchronized(() => _writeAllUnlocked(sessions));
  }

  Future<void> _writeAllUnlocked(List<SessionListEntry> sessions) async {
    final payload = <String, Object?>{
      'version': indexVersion,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'sessions': [for (final session in sessions) session.toJson()],
    };
    await _fs.writeText(
      _indexFile,
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  /// Replaces an existing [entry] in place, or appends when the id is new.
  Future<void> upsert(SessionListEntry entry) {
    return _mutationLock.synchronized(() async {
      final current = await tryRead() ?? <SessionListEntry>[];
      final id = entry.sessionId;
      var replaced = false;
      final next = <SessionListEntry>[];
      for (final existing in current) {
        if (existing.sessionId != id) {
          next.add(existing);
          continue;
        }
        if (replaced) continue;
        next.add(entry);
        replaced = true;
      }
      if (!replaced) next.add(entry);
      await _writeAllUnlocked(next);
    });
  }

  Future<void> remove(String sessionId) {
    return _mutationLock.synchronized(() async {
      final trimmed = sessionId.trim();
      if (trimmed.isEmpty) return;
      final current = await tryRead();
      if (current == null) return;
      final next = current
          .where((session) => session.sessionId != trimmed)
          .toList(growable: false);
      if (next.length == current.length) return;
      await _writeAllUnlocked(next);
    });
  }
}
