import 'dart:io';

import '../../models/workspace_icon_ref.dart';
import '../io/filesystem.dart';
import 'workspace_icon_storage.dart';

/// Applies [WorkspaceIconRef] transitions and loads custom icon bytes with cache.
///
/// Disk access is home-plane: repositories pin a [WorkspaceIconStorage] via
/// `storage:`; the shared app-scoped [workspaceIconService] instance keeps only
/// the in-memory bytes cache and takes the caller's [Filesystem] per read
/// instead (UI call sites thread their injected home storage).
class WorkspaceIconService {
  WorkspaceIconService({WorkspaceIconStorage? storage})
    : _storageOverride = storage;

  final WorkspaceIconStorage? _storageOverride;
  final _bytesCache = <String, List<int>>{};

  WorkspaceIconStorage _disk(Filesystem? filesystem) {
    final pinned = _storageOverride;
    if (pinned != null) return pinned;
    if (filesystem != null) return WorkspaceIconStorage(filesystem: filesystem);
    throw StateError(
      'WorkspaceIconService requires a disk layer: construct it with '
      '`storage:` or pass `filesystem:` to the disk-touching call.',
    );
  }

  String _cacheKey(String workspaceDir, String relativePath) =>
      '$workspaceDir|$relativePath';

  void evictCustomIconCache({
    required String workspaceDir,
    required String relativePath,
  }) {
    _bytesCache.remove(_cacheKey(workspaceDir, relativePath));
  }

  void evictWorkspaceCustomIcons({
    required String workspaceDir,
    required String workspaceId,
    WorkspaceIconRef? icon,
  }) {
    if (icon case WorkspaceIconCustom(
      :final relativePath,
    ) when relativePath.isNotEmpty) {
      evictCustomIconCache(
        workspaceDir: workspaceDir,
        relativePath: relativePath,
      );
    }
    _bytesCache.removeWhere(
      (key, _) => key.startsWith(
        '$workspaceDir|${WorkspaceIconStorage.assetsDirName}/',
      ),
    );
  }

  Future<List<int>?> loadCustomBytes({
    required String workspaceDir,
    required String relativePath,
    required Filesystem filesystem,
  }) async {
    final cacheKey = _cacheKey(workspaceDir, relativePath);
    final cached = _bytesCache[cacheKey];
    if (cached != null) return cached;

    final bytes = await _disk(filesystem).readBytes(
      workspaceDir: workspaceDir,
      relativePath: relativePath,
    );
    if (bytes == null || bytes.isEmpty) return null;
    _bytesCache[cacheKey] = bytes;
    return bytes;
  }

  Future<WorkspaceIconCustom> importCustomFromLocalFile({
    required String workspaceDir,
    required String workspaceId,
    required String localSourcePath,
    Filesystem? filesystem,
  }) async {
    final ext = _extension(localSourcePath);
    if (!WorkspaceIconStorage.isAllowedExtension(ext)) {
      throw WorkspaceIconImportException('Unsupported file type: .$ext');
    }

    final bytes = await File(localSourcePath).readAsBytes();
    if (bytes.isEmpty) {
      throw WorkspaceIconImportException('Icon file is empty');
    }

    final relativePath = await _disk(filesystem).saveBytes(
      workspaceDir: workspaceDir,
      workspaceId: workspaceId,
      bytes: bytes,
      extension: ext,
    );
    if (relativePath == null) {
      throw WorkspaceIconImportException('Could not save icon file');
    }

    evictWorkspaceCustomIcons(
      workspaceDir: workspaceDir,
      workspaceId: workspaceId,
    );
    return WorkspaceIconCustom(relativePath);
  }

  Future<void> deleteCustomFilesForTransition({
    required String workspaceDir,
    required String workspaceId,
    required WorkspaceIconRef previous,
    required WorkspaceIconRef next,
    Filesystem? filesystem,
  }) async {
    if (previous is! WorkspaceIconCustom || !previous.isValid) return;
    if (next is WorkspaceIconCustom &&
        next.relativePath == previous.relativePath) {
      return;
    }
    await _disk(filesystem).deleteFile(
      workspaceDir: workspaceDir,
      relativePath: previous.relativePath,
    );
    evictCustomIconCache(
      workspaceDir: workspaceDir,
      relativePath: previous.relativePath,
    );
  }

  Future<void> deleteAllCustomFilesForWorkspace({
    required String workspaceDir,
    required String workspaceId,
    WorkspaceIconRef? icon,
    Filesystem? filesystem,
  }) async {
    if (icon case WorkspaceIconCustom(
      :final relativePath,
    ) when relativePath.isNotEmpty) {
      await _disk(filesystem).deleteFile(
        workspaceDir: workspaceDir,
        relativePath: relativePath,
      );
    }
    await _disk(filesystem).deleteAllForWorkspace(
      workspaceDir: workspaceDir,
      workspaceId: workspaceId,
    );
    evictWorkspaceCustomIcons(
      workspaceDir: workspaceDir,
      workspaceId: workspaceId,
      icon: icon,
    );
  }

  String _extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return '';
    return path.substring(dot + 1).toLowerCase();
  }
}

class WorkspaceIconImportException implements Exception {
  WorkspaceIconImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Shared app-scoped instance for UI reads (bytes cache only — disk reads pass
/// the caller's home-plane [Filesystem]); repositories construct their own with
/// a pinned `storage:` for tests and mutations.
WorkspaceIconService workspaceIconService = WorkspaceIconService();
