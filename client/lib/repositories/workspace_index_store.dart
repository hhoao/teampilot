import 'dart:convert';

import '../models/workspace.dart';
import '../services/io/local_filesystem.dart';
import '../utils/logger.dart';
import 'index_snapshot_isolate.dart';
import 'session_repository_fs.dart';

/// Derived snapshot of workspace manifests plus session directory ids.
///
/// [manifest.json] remains source of truth; this file is updated on every
/// repository mutation so startup can read one JSON file instead of scanning
/// every workspace directory.
class WorkspaceIndexStore {
  WorkspaceIndexStore(this._fs);

  final SessionRepositoryFs _fs;

  static const indexVersion = 1;

  String get _indexFile => _fs.layout.workspacesIndexFile;

  Future<List<Workspace>?> tryRead() async {
    final indexFile = _indexFile;
    if (_fs.fs is LocalFilesystem) {
      try {
        final maps = await IndexSnapshotIsolate.readWorkspacesMaps(indexFile);
        final workspaces = _workspacesFromMaps(maps);
        if (workspaces != null) {
          appLogger.i('[boot] workspaces-index read via isolate');
          return workspaces;
        }
      } on Object {
        // Fall back to filesystem abstraction (WSL / SSH).
      }
    }
    final raw = await _fs.readText(indexFile);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      if (decoded['version'] != indexVersion) return null;
      final list = decoded['workspaces'];
      if (list is! List) return null;
      return _workspacesFromMaps([
        for (final item in list)
          if (item is Map) Map<String, Object?>.from(item),
      ]);
    } on Object {
      return null;
    }
  }

  List<Workspace>? _workspacesFromMaps(List<Map<String, Object?>>? maps) {
    if (maps == null) return null;
    final workspaces = <Workspace>[];
    for (final item in maps) {
      final workspace = Workspace.fromJson(item);
      if (workspace.workspaceId.isEmpty) return null;
      workspaces.add(workspace);
    }
    return workspaces;
  }

  Future<void> writeAll(List<Workspace> workspaces) async {
    final payload = <String, Object?>{
      'version': indexVersion,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'workspaces': [for (final workspace in workspaces) workspace.toJson()],
    };
    await _fs.writeText(
      _indexFile,
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Future<void> upsert(Workspace workspace) async {
    final current = await tryRead() ?? <Workspace>[];
    final id = workspace.workspaceId;
    final next = <Workspace>[
      for (final existing in current)
        if (existing.workspaceId != id) existing,
      workspace,
    ];
    await writeAll(next);
  }

  Future<void> remove(String workspaceId) async {
    final trimmed = workspaceId.trim();
    if (trimmed.isEmpty) return;
    final current = await tryRead();
    if (current == null) return;
    final next = current
        .where((workspace) => workspace.workspaceId != trimmed)
        .toList(growable: false);
    if (next.length == current.length) return;
    await writeAll(next);
  }
}
