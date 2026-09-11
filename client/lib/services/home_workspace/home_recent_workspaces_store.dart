import 'dart:convert';

import '../../models/workspace_tab_ref.dart';
import '../io/filesystem.dart';
import '../storage/home_storage.dart';

/// Persists recently visited workspace tabs (directory + launch identity).
class HomeRecentWorkspacesStore {
  HomeRecentWorkspacesStore({
    required HomeStorage storage,
    Filesystem? fs,
    String? pathOverride,
  }) : _storage = storage,
       _fsOverride = fs,
       _pathOverride = pathOverride;

  static const maxEntries = 30;

  final HomeStorage _storage;
  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? _storage.fs;
  String get _path =>
      _pathOverride ?? _storage.paths.homeWorkspaceRecentWorkspacesJson;

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

  Future<void> recordVisit(WorkspaceTabRef tab) async {
    if (tab.workspaceId.trim().isEmpty) return;
    final existing = await loadOrderedTabs();
    final next = [
      tab,
      for (final entry in existing)
        if (entry.tabKey != tab.tabKey) entry,
    ].take(maxEntries).toList();
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(_path));
    await _fs.atomicWrite(
      _path,
      jsonEncode({'tabs': next.map((t) => t.toJson()).toList()}),
    );
  }
}
