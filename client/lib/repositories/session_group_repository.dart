import 'dart:convert';

import '../models/session_group.dart';
import '../services/io/filesystem.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/workspace_layout.dart';
import '../utils/logging/logger_utils.dart';

/// Reads and writes `{workspaceDir}/session-groups.json` — manual sidebar
/// session groups for one workspace. Corrupt or missing files decode to an
/// empty document (corruption is logged as a warning); the next save rebuilds
/// the file.
class SessionGroupRepository {
  SessionGroupRepository({Filesystem? fs, WorkspaceLayout? layout})
    : _fs = fs ?? AppStorage.fs,
      _layout =
          layout ?? WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);

  final Filesystem _fs;
  final WorkspaceLayout _layout;
  final Map<String, SessionGroupsFile> _cache = {};

  Future<SessionGroupsFile> load(String workspaceId) async {
    final id = workspaceId.trim();
    if (id.isEmpty) return const SessionGroupsFile();
    final cached = _cache[id];
    if (cached != null) return cached;

    final path = _file(id);
    final raw = await _fs.readString(path);
    if (raw == null || raw.trim().isEmpty) {
      return _cache[id] = const SessionGroupsFile();
    }
    final decoded = _decodeTolerantly(id, raw);
    return _cache[id] = decoded ?? const SessionGroupsFile();
  }

  /// Best-effort decode; logs and returns null when the document is corrupt
  /// so the caller starts from (and later rewrites) an empty document.
  SessionGroupsFile? _decodeTolerantly(String workspaceId, String raw) {
    Object? decoded;
    Object? failure;
    try {
      decoded = jsonDecode(raw);
    } on Object catch (error) {
      failure = error;
    }
    if (failure == null && decoded is! Map) {
      failure = 'unexpected ${decoded.runtimeType} payload';
    }
    if (failure != null) {
      AppLogger.instance.w(
        'Corrupt session-groups.json for workspace "$workspaceId" ($failure); '
        'starting from an empty document.',
        error: failure,
      );
      return null;
    }
    return SessionGroupsFile.fromJson((decoded as Map).cast<String, Object?>());
  }

  Future<void> save(String workspaceId, SessionGroupsFile file) async {
    final id = workspaceId.trim();
    if (id.isEmpty) return;
    _cache[id] = file;
    final path = _file(id);
    await _fs.ensureDir(_fs.pathContext.dirname(path));
    await _fs.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(file.toJson()),
    );
  }

  void invalidate(String workspaceId) => _cache.remove(workspaceId.trim());

  String _file(String workspaceId) =>
      _layout.sessionGroupsFile(workspaceId.trim());
}
