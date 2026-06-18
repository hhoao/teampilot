import 'dart:convert';

import '../../models/home_closed_project_entry.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Persists recently closed title-bar project tabs (most recent first).
class HomeClosedWorkspacesStore {
  HomeClosedWorkspacesStore({Filesystem? fs, String? pathOverride})
      : _fsOverride = fs,
        _pathOverride = pathOverride;

  static const maxEntries = 20;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path =>
      _pathOverride ?? AppStorage.paths.homeWorkspaceClosedProjectsJson;

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
        final entry = HomeClosedWorkspaceEntry.fromJson(
          raw.cast<String, Object?>(),
        );
        if (entry.projectId.isNotEmpty) parsed.add(entry);
      }
      parsed.sort((a, b) => b.closedAt.compareTo(a.closedAt));
      return parsed;
    } catch (_) {
      return [];
    }
  }

  Future<void> recordClosed(HomeClosedWorkspaceEntry entry) async {
    final trimmedId = entry.projectId.trim();
    if (trimmedId.isEmpty) return;
    final existing = await load();
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = [
      HomeClosedWorkspaceEntry(
        projectId: trimmedId,
        displayName: entry.displayName,
        primaryPath: entry.primaryPath,
        closedAt: now,
      ),
      for (final e in existing)
        if (e.projectId != trimmedId) e,
    ].take(maxEntries).toList();
    await _save(next);
  }

  Future<void> remove(String projectId) async {
    final trimmed = projectId.trim();
    if (trimmed.isEmpty) return;
    final next = [
      for (final e in await load())
        if (e.projectId != trimmed) e,
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
