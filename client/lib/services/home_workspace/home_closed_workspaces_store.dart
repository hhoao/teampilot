import 'dart:convert';

import '../../models/home_closed_workspace_entry.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Persists recently closed title-bar workspace tabs (most recent first).
class HomeClosedWorkspacesStore {
  HomeClosedWorkspacesStore({Filesystem? fs, String? pathOverride})
      : _fsOverride = fs,
        _pathOverride = pathOverride;

  static const maxEntries = 20;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path =>
      _pathOverride ?? AppStorage.paths.homeWorkspaceClosedWorkspacesJson;

  Future<List<HomeClosedWorkspaceEntry>> load() async {
    try {
      final text = await _fs.readString(_path);
      if (text == null || text.isEmpty) return [];
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      final entries = root['entries'];
      if (entries is! List) return [];
      final parsed = <HomeClosedWorkspaceEntry>[];
      for (final raw in entries) {
        if (raw is! Map) continue;
        try {
          final entry = HomeClosedWorkspaceEntry.fromJson(
            raw.cast<String, Object?>(),
          );
          parsed.add(entry);
        } catch (_) {
          continue;
        }
      }
      parsed.sort((a, b) => b.closedAt.compareTo(a.closedAt));
      return parsed;
    } catch (_) {
      return [];
    }
  }

  Future<void> recordClosed(HomeClosedWorkspaceEntry entry) async {
    final trimmedId = entry.workspaceId.trim();
    if (trimmedId.isEmpty) return;
    final existing = await load();
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = [
      HomeClosedWorkspaceEntry(
        workspaceId: trimmedId,
        displayName: entry.displayName,
        primaryPath: entry.primaryPath,
        closedAt: now,
        identity: entry.identity,
        topology: entry.topology,
      ),
      for (final e in existing)
        if (e.tabKey != entry.tabKey) e,
    ].take(maxEntries).toList();
    await _save(next);
  }

  Future<void> remove(String tabKey) async {
    final trimmed = tabKey.trim();
    if (trimmed.isEmpty) return;
    final next = [
      for (final e in await load())
        if (e.tabKey != trimmed) e,
    ];
    await _save(next);
  }

  Future<void> _save(List<HomeClosedWorkspaceEntry> entries) async {
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(_path));
    await _fs.atomicWrite(
      _path,
      jsonEncode({
        'entries': [for (final e in entries) e.toJson()],
      }),
    );
  }
}
