import 'dart:convert';

import '../../../utils/lock_pool.dart';
import '../../io/filesystem.dart';
import '../../storage/runtime_layout.dart';
import '../registry/capabilities/cli_session_lifecycle_capability.dart';
import 'cli_session_manifest.dart';

/// Reads and writes `init.json` for CLI session lifecycle with session-level locking.
class CliSessionManifestStore {
  CliSessionManifestStore({
    required Filesystem fs,
    required RuntimeLayout layout,
  }) : _fs = fs,
       _layout = layout;

  final Filesystem _fs;
  final RuntimeLayout _layout;

  static final _sessionLocks = LockPool();

  Future<CliSessionManifest?> read({
    required String workspaceId,
    required String sessionId,
    required String tool,
  }) {
    return _synchronized(
      workspaceId: workspaceId,
      sessionId: sessionId,
      tool: tool,
      fn: () => _readAtPath(_manifestPath(workspaceId, sessionId, tool)),
    );
  }

  Future<void> write({
    required String workspaceId,
    required String sessionId,
    required String tool,
    required CliSessionManifest manifest,
  }) {
    return _synchronized(
      workspaceId: workspaceId,
      sessionId: sessionId,
      tool: tool,
      fn: () async {
        final path = _manifestPath(workspaceId, sessionId, tool);
        await _writeAtPath(path, manifest);
      },
    );
  }

  Future<CliSessionManifest?> updatePhase({
    required String workspaceId,
    required String sessionId,
    required String tool,
    required CliSessionPhase phase,
    int? phaseUpdatedAtMs,
  }) {
    return _synchronized(
      workspaceId: workspaceId,
      sessionId: sessionId,
      tool: tool,
      fn: () async {
        final path = _manifestPath(workspaceId, sessionId, tool);
        final existing = await _readAtPath(path);
        if (existing == null) return null;

        final updated = existing.copyWith(
          phase: phase,
          phaseUpdatedAtMs:
              phaseUpdatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
        );
        await _writeAtPath(path, updated);
        return updated;
      },
    );
  }

  Future<CliSessionManifest?> _readAtPath(String path) async {
    final raw = await _fs.readString(path);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      return CliSessionManifest.fromJson(json.cast<String, Object?>());
    } on Object {
      return null;
    }
  }

  Future<void> _writeAtPath(String path, CliSessionManifest manifest) async {
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(path));
    await _fs.atomicWrite(path, jsonEncode(manifest.toJson()));
  }

  String _manifestPath(String workspaceId, String sessionId, String tool) {
    final ctx = _fs.pathContext;
    return ctx.join(
      _layout.workspace.sessionRuntimeDir(workspaceId, sessionId),
      '_shared',
      tool.trim(),
      'init.json',
    );
  }

  String _lockKey(String workspaceId, String sessionId, String tool) =>
      '${workspaceId.trim()}|${sessionId.trim()}|${tool.trim()}';

  Future<T> _synchronized<T>({
    required String workspaceId,
    required String sessionId,
    required String tool,
    required Future<T> Function() fn,
  }) {
    return _sessionLocks.synchronized(
      _lockKey(workspaceId, sessionId, tool),
      fn,
    );
  }
}
