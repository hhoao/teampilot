import 'dart:convert';

import '../models/workspace_project_config.dart';
import '../services/io/filesystem.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/workspace_layout.dart';

/// Reads and writes `{workspaceDir}/project-config.json`.
class WorkspaceProjectConfigRepository {
  WorkspaceProjectConfigRepository({
    Filesystem? fs,
    WorkspaceLayout? layout,
  }) : _fs = fs ?? AppStorage.fs,
       _layout = layout ?? WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);

  final Filesystem _fs;
  final WorkspaceLayout _layout;
  final Map<String, WorkspaceProjectConfig> _cache = {};

  String _file(String workspaceId) =>
      _layout.projectConfigFile(workspaceId.trim());

  Future<WorkspaceProjectConfig> load(String workspaceId) async {
    final id = workspaceId.trim();
    if (id.isEmpty) return const WorkspaceProjectConfig();
    final cached = _cache[id];
    if (cached != null) return cached;

    final path = _file(id);
    final raw = await _fs.readString(path);
    if (raw == null || raw.trim().isEmpty) {
      return _cache[id] = const WorkspaceProjectConfig();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return _cache[id] = WorkspaceProjectConfig.fromJson(
          decoded.cast<String, Object?>(),
        );
      }
    } on Object {
      // Corrupt file → empty; next save overwrites.
    }
    return _cache[id] = const WorkspaceProjectConfig();
  }

  Future<void> save(String workspaceId, WorkspaceProjectConfig config) async {
    final id = workspaceId.trim();
    if (id.isEmpty) return;
    _cache[id] = config;
    final path = _file(id);
    await _fs.ensureDir(_fs.pathContext.dirname(path));
    await _fs.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );
  }

  Future<WorkspaceProjectConfig> updateBundle(
    String workspaceId,
    WorkspaceProjectConfig Function(WorkspaceProjectConfig current) mutate,
  ) async {
    final current = await load(workspaceId);
    final next = mutate(current);
    await save(workspaceId, next);
    return next;
  }

  void invalidate(String workspaceId) {
    _cache.remove(workspaceId.trim());
  }

  void clearCache() => _cache.clear();
}
