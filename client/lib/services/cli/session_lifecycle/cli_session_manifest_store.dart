import 'dart:convert';

import '../../../utils/lock_pool.dart';
import '../../io/filesystem.dart';
import '../../storage/runtime_layout.dart';
import '../registry/capabilities/cli_session_lifecycle_capability.dart';
import 'cli_session_manifest.dart';

/// Reads and writes workspace+team `init.json` for CLI lifecycle warm tier.
class CliSessionManifestStore {
  CliSessionManifestStore({
    required Filesystem fs,
    required RuntimeLayout layout,
  }) : _fs = fs,
       _layout = layout;

  final Filesystem _fs;
  final RuntimeLayout _layout;

  static final _workspaceLocks = LockPool();
  final Map<String, CliSessionManifest> _peekCache = {};

  /// Last manifest read or written for this workspace+team tool (sync gate reads).
  CliSessionManifest? peek({
    required String workspaceId,
    required String teamId,
    required String tool,
  }) =>
      _peekCache[_lockKey(workspaceId, teamId, tool)];

  Future<CliSessionManifest?> read({
    required String workspaceId,
    required String teamId,
    required String tool,
  }) {
    return _synchronized(
      workspaceId: workspaceId,
      teamId: teamId,
      tool: tool,
      fn: () => _readAtPath(
        _manifestPath(workspaceId, teamId, tool),
        workspaceId: workspaceId,
        teamId: teamId,
        tool: tool,
      ),
    );
  }

  Future<void> write({
    required String workspaceId,
    required String teamId,
    required String tool,
    required CliSessionManifest manifest,
  }) {
    return _synchronized(
      workspaceId: workspaceId,
      teamId: teamId,
      tool: tool,
      fn: () async {
        final path = _manifestPath(workspaceId, teamId, tool);
        await _writeAtPath(
          path,
          manifest,
          workspaceId: workspaceId,
          teamId: teamId,
          tool: tool,
        );
      },
    );
  }

  /// Read-merge-write under the workspace+team lock so concurrent callers
  /// cannot clobber a newer phase.
  Future<CliSessionManifest> merge({
    required String workspaceId,
    required String teamId,
    required String tool,
    required CliSessionManifest Function(CliSessionManifest? existing) merge,
  }) {
    return _synchronized(
      workspaceId: workspaceId,
      teamId: teamId,
      tool: tool,
      fn: () async {
        final path = _manifestPath(workspaceId, teamId, tool);
        final existing = await _readAtPath(
          path,
          workspaceId: workspaceId,
          teamId: teamId,
          tool: tool,
        );
        final merged = merge(existing);
        await _writeAtPath(
          path,
          merged,
          workspaceId: workspaceId,
          teamId: teamId,
          tool: tool,
        );
        return merged;
      },
    );
  }

  Future<CliSessionManifest?> updatePhase({
    required String workspaceId,
    required String teamId,
    required String tool,
    required CliSessionPhase phase,
    int? phaseUpdatedAtMs,
  }) {
    return _synchronized(
      workspaceId: workspaceId,
      teamId: teamId,
      tool: tool,
      fn: () async {
        final path = _manifestPath(workspaceId, teamId, tool);
        final existing = await _readAtPath(
          path,
          workspaceId: workspaceId,
          teamId: teamId,
          tool: tool,
        );
        if (existing == null) return null;

        final updated = existing.copyWith(
          phase: phase,
          phaseUpdatedAtMs:
              phaseUpdatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
        );
        await _writeAtPath(
          path,
          updated,
          workspaceId: workspaceId,
          teamId: teamId,
          tool: tool,
        );
        return updated;
      },
    );
  }

  Future<CliSessionManifest?> _readAtPath(
    String path, {
    required String workspaceId,
    required String teamId,
    required String tool,
  }) async {
    final raw = await _fs.readString(path);
    if (raw == null || raw.trim().isEmpty) {
      _peekCache.remove(_lockKey(workspaceId, teamId, tool));
      return null;
    }
    try {
      final json = jsonDecode(raw);
      if (json is! Map) {
        _peekCache.remove(_lockKey(workspaceId, teamId, tool));
        return null;
      }
      final manifest = CliSessionManifest.fromJson(
        json.cast<String, Object?>(),
      );
      _peekCache[_lockKey(workspaceId, teamId, tool)] = manifest;
      return manifest;
    } on Object {
      _peekCache.remove(_lockKey(workspaceId, teamId, tool));
      return null;
    }
  }

  Future<void> _writeAtPath(
    String path,
    CliSessionManifest manifest, {
    required String workspaceId,
    required String teamId,
    required String tool,
  }) async {
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(path));
    await _fs.atomicWrite(path, jsonEncode(manifest.toJson()));
    _peekCache[_lockKey(workspaceId, teamId, tool)] = manifest;
  }

  String _manifestPath(String workspaceId, String teamId, String tool) {
    return _layout.workspaceLifecycleManifestPath(workspaceId, teamId, tool);
  }

  String _lockKey(String workspaceId, String teamId, String tool) =>
      '${workspaceId.trim()}|${teamId.trim()}|${tool.trim()}';

  Future<T> _synchronized<T>({
    required String workspaceId,
    required String teamId,
    required String tool,
    required Future<T> Function() fn,
  }) {
    return _workspaceLocks.synchronized(
      _lockKey(workspaceId, teamId, tool),
      fn,
    );
  }
}
