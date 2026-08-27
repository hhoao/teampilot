import 'dart:convert';

import '../../models/failed_message_record.dart';
import '../../utils/lock_pool.dart';
import '../io/filesystem.dart';
import '../storage/workspace_layout.dart';

/// Persists delivery-state records in their owning session directory.
class FailedMessageStore {
  FailedMessageStore({required Filesystem fs, required String rootPath})
    : _fs = fs,
      _layout = WorkspaceLayout(teampilotRoot: rootPath, fs: fs);

  final Filesystem _fs;
  final WorkspaceLayout _layout;

  static final _mutationLocks = LockPool();

  Future<List<FailedMessageRecord>> load(
    String workspaceId,
    String sessionId,
  ) async {
    try {
      final text = await _fs.readString(
        _layout.failedMessagesFile(workspaceId, sessionId),
      );
      if (text == null || text.isEmpty) return const [];
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      final entries = root['records'];
      if (entries is! List) return const [];
      return [
        for (final entry in entries)
          if (entry is Map)
            if (FailedMessageRecord.fromJson(entry.cast<String, Object?>())
                case final record?)
              record,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Adds [record], or replaces the existing record with the same id.
  Future<void> save(
    String workspaceId,
    String sessionId,
    FailedMessageRecord record,
  ) => _mutationLocks.synchronized(_lockKey(workspaceId, sessionId), () async {
    final records = List.of(await load(workspaceId, sessionId));
    final index = records.indexWhere((item) => item.id == record.id);
    if (index < 0) {
      records.add(record);
    } else {
      records[index] = record;
    }
    await _write(workspaceId, sessionId, records);
  });

  Future<void> remove(String workspaceId, String sessionId, String recordId) =>
      _mutationLocks.synchronized(_lockKey(workspaceId, sessionId), () async {
        final records = List.of(await load(workspaceId, sessionId))
          ..removeWhere((record) => record.id == recordId);
        await _write(workspaceId, sessionId, records);
      });

  String _lockKey(String workspaceId, String sessionId) =>
      '${workspaceId.trim()}/${sessionId.trim()}';

  Future<void> _write(
    String workspaceId,
    String sessionId,
    List<FailedMessageRecord> records,
  ) async {
    final file = _layout.failedMessagesFile(workspaceId, sessionId);
    await _fs.ensureDir(_fs.pathContext.dirname(file));
    await _fs.atomicWrite(
      file,
      jsonEncode({
        'version': 1,
        'records': records.map((record) => record.toJson()).toList(),
      }),
    );
  }
}
