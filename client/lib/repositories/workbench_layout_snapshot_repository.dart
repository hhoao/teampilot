import 'dart:convert';

import '../cubits/workbench/workbench_cubit.dart';
import '../cubits/workbench/workbench_split_layout.dart';
import '../cubits/workbench/tab_strip.dart';
import '../cubits/workbench/workbench_tab.dart';
import '../services/io/filesystem.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/workspace_layout.dart';
import '../utils/logging/logger.dart';

/// Persists one workspace's workbench split-layout snapshot at
/// `<teampilotRoot>/workspace/workspaces/{id}/workbench-layout.json`:
///
/// ```json
/// {"center": <Task 1 layout snapshot>, "floating": <Task 1 layout snapshot>, "version": 1}
/// ```
///
/// Mirrors [AutomationRepository]'s per-workspace JSON conventions: an
/// injected [Filesystem] + [WorkspaceLayout] (tests inject a fake), all IO
/// failures and corrupt input are logged via [appLogger] and swallowed —
/// [restore] never throws to the caller and simply leaves the bar at its
/// current (single-group fallback) state.
class WorkbenchLayoutSnapshotRepository {
  WorkbenchLayoutSnapshotRepository({
    required this.workspaceId,
    Filesystem? fs,
    WorkspaceLayout? layout,
  }) : _fs = fs ?? AppStorage.fs,
       _layout =
           layout ?? WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);

  final String workspaceId;
  final Filesystem _fs;
  final WorkspaceLayout _layout;

  /// Snapshot format version. A persisted file whose `version` differs is
  /// treated as corrupt (restore falls back to the current bar).
  static const int currentVersion = 1;

  String get _file => _layout.workbenchLayoutFile(workspaceId);

  /// Writes both layout snapshots atomically. IO errors are logged, never
  /// thrown — persistence must not break tab interaction.
  Future<void> save(
    WorkbenchGroupLayout center,
    WorkbenchGroupLayout floating,
  ) async {
    final encoded = jsonEncode({
      'version': currentVersion,
      'center': toSnapshot(center),
      'floating': toSnapshot(floating),
    });
    try {
      await _fs.ensureDir(_layout.workspaceDir(workspaceId));
      await _fs.atomicWrite(_file, encoded);
    } on Object catch (e) {
      appLogger.w('[workbench-layout] save failed ($workspaceId): $e');
    }
  }

  /// Applies the persisted snapshot to [workbench] via
  /// [WorkbenchCubit.resetLayoutToSnapshot].
  ///
  /// - [tabResolves] gates every persisted tab id: tabs it rejects are pruned
  ///   and groups left empty are rolled up (Task 1 `layoutFromSnapshot`).
  ///   Session ids should resolve against ChatCubit's sessions/tab store;
  ///   every other kind resolves true (domain sync strips stale ids on its
  ///   own, per `WorkbenchShellRunSync` precedent). Defaults to all-true.
  /// - Missing, corrupt, or version-mismatched files leave the bar at its
  ///   current state (single-group fallback) after an [appLogger] warning.
  /// - A surface whose snapshot decodes to null (nothing survives pruning)
  ///   keeps its current layout; the other surface still restores.
  /// - Runtime landing state never resurrects: a strip restored with tabs but
  ///   no active tab gets its first tab activated (landing draft/return fields
  ///   are not persisted at all).
  Future<void> restore(
    WorkbenchCubit workbench, {
    bool Function(WorkbenchTabId tab)? tabResolves,
  }) async {
    final resolve = tabResolves ?? (_) => true;
    final Map<String, Object?>? json = await _readSnapshot();
    if (json == null) return;

    final centerJson = json['center'];
    final floatingJson = json['floating'];
    if (centerJson is! Map || floatingJson is! Map) {
      appLogger.w(
        '[workbench-layout] corrupt snapshot ($workspaceId): '
        'center/floating must be objects',
      );
      return;
    }

    final WorkbenchGroupLayout? center;
    final WorkbenchGroupLayout? floating;
    try {
      final decodedCenter = layoutFromSnapshot(
        Map<String, Object?>.from(centerJson),
        tabResolves: resolve,
      );
      final decodedFloating = layoutFromSnapshot(
        Map<String, Object?>.from(floatingJson),
        tabResolves: resolve,
      );
      center = decodedCenter == null ? null : _withoutRuntimeLanding(decodedCenter);
      floating =
          decodedFloating == null ? null : _withoutRuntimeLanding(decodedFloating);
    } on Object catch (e) {
      appLogger.w(
        '[workbench-layout] corrupt snapshot ($workspaceId): $e',
      );
      return;
    }

    if (center == null && floating == null) {
      appLogger.w(
        '[workbench-layout] snapshot pruned to empty ($workspaceId); '
        'keeping current layout',
      );
      return;
    }
    workbench.resetLayoutToSnapshot(workspaceId, center, floating);
  }

  /// Landing is runtime-only: the snapshot encodes "landing shown" as a
  /// strip's null [TabStrip.activeId], while the other landing fields (draft
  /// text, return tab) are dropped entirely by `toSnapshot`. Reviving the
  /// first tab keeps a restored group that still has tabs out of a degraded,
  /// draft-less landing — the same "neighbor → first" fallback
  /// [TabStripReducer.remove] applies when the active tab disappears.
  WorkbenchGroupLayout _withoutRuntimeLanding(WorkbenchGroupLayout layout) {
    var revived = false;
    final groups = <String, TabStrip>{
      for (final entry in layout.groups.entries)
        entry.key: () {
          final strip = entry.value;
          if (strip.activeId != null || strip.order.isEmpty) return strip;
          revived = true;
          return strip.copyWith(activeId: strip.order.first);
        }(),
    };
    return revived ? layout.copyWith(groups: groups) : layout;
  }

  /// Removes the snapshot file (workspace removal already wipes the whole
  /// workspace directory — see `SessionRepositoryFs.deleteWorkspaceDir` — so
  /// this is only needed for explicit clears).
  Future<void> delete() async {
    try {
      await _fs.removeRecursive(_file);
    } on Object catch (e) {
      appLogger.w('[workbench-layout] delete failed ($workspaceId): $e');
    }
  }

  /// Reads and shape-checks the snapshot. Null when absent, unreadable,
  /// undecodable, non-object, or version-mismatched (all logged except the
  /// benign absent/empty case).
  Future<Map<String, Object?>?> _readSnapshot() async {
    final String? raw;
    try {
      raw = await _fs.readString(_file);
    } on Object catch (e) {
      appLogger.w('[workbench-layout] read failed ($workspaceId): $e');
      return null;
    }
    if (raw == null || raw.trim().isEmpty) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on Object catch (e) {
      appLogger.w('[workbench-layout] corrupt snapshot ($workspaceId): $e');
      return null;
    }
    if (decoded is! Map) {
      appLogger.w(
        '[workbench-layout] corrupt snapshot ($workspaceId): '
        'expected a JSON object',
      );
      return null;
    }
    final json = Map<String, Object?>.from(decoded);
    if (json['version'] != currentVersion) {
      appLogger.w(
        '[workbench-layout] unsupported snapshot version ($workspaceId): '
        '${json['version']} != $currentVersion',
      );
      return null;
    }
    return json;
  }
}
