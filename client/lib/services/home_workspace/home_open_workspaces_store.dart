import 'dart:convert';

import '../../models/workspace_tab_ref.dart';
import '../io/filesystem.dart';
import '../storage/home_storage.dart';

/// Persists open title-bar workspace tabs in display order.
class HomeOpenWorkspacesStore {
  HomeOpenWorkspacesStore({
    required HomeStorage storage,
    Filesystem? fs,
    String? pathOverride,
  }) : _storage = storage,
       _fsOverride = fs,
       _pathOverride = pathOverride;

  final HomeStorage _storage;
  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? _storage.fs;
  String get _path =>
      _pathOverride ?? _storage.paths.homeWorkspaceOpenWorkspacesJson;

  Future<List<WorkspaceTabRef>> loadOrderedTabs() async {
    try {
      final text = await _fs.readString(_path);
      if (text == null || text.isEmpty) return [];
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      final tabsRaw = root['tabs'];
      if (tabsRaw is! List) return [];
      final parsed = <WorkspaceTabRef>[];
      for (final entry in tabsRaw) {
        if (entry is! Map) continue;
        try {
          parsed.add(WorkspaceTabRef.fromJson(entry.cast<String, Object?>()));
        } catch (_) {
          continue;
        }
      }
      return parsed;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveOrderedTabs(List<WorkspaceTabRef> tabs) async {
    final next = [
      for (final tab in tabs)
        if (tab.workspaceId.trim().isNotEmpty) tab,
    ];
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(_path));
    await _fs.atomicWrite(
      _path,
      jsonEncode({'tabs': next.map((t) => t.toJson()).toList()}),
    );
  }
}
