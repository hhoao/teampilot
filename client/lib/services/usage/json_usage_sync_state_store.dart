import 'dart:convert';

import '../../models/session_usage_sync_state.dart';
import '../io/filesystem.dart';

final class JsonUsageSyncStateStore {
  JsonUsageSyncStateStore({required Filesystem fs, required String filePath})
    : _fs = fs,
      _path = filePath;

  final Filesystem _fs;
  final String _path;

  Future<UsageSyncState> load() async {
    final raw = await _fs.readString(_path);
    if (raw == null || raw.trim().isEmpty) return const UsageSyncState();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const UsageSyncState();
      return UsageSyncState.fromJson(Map<String, Object?>.from(decoded));
    } on Object {
      return const UsageSyncState();
    }
  }

  Future<void> save(UsageSyncState state) {
    return _fs.atomicWrite(
      _path,
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
    );
  }
}
