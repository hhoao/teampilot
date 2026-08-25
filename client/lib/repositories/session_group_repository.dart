import 'dart:convert';

import '../models/session_group.dart';
import '../services/io/filesystem.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/workspace_layout.dart';

/// Reads and writes `{workspaceDir}/session-groups.json` — manual sidebar
/// session groups for one workspace. Corrupt or missing files decode to an
/// empty document; the next save rebuilds the file.
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
    return _cache[id] = SessionGroupsFile.fromRawJson(raw);
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
