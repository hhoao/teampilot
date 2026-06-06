import 'dart:io';

import '../../models/project_icon_ref.dart';
import 'project_icon_storage.dart';

/// Applies [ProjectIconRef] transitions and loads custom icon bytes with cache.
class ProjectIconService {
  ProjectIconService({ProjectIconStorage? storage})
    : _storage = storage ?? ProjectIconStorage();

  final ProjectIconStorage _storage;
  final _bytesCache = <String, List<int>>{};

  String _cacheKey(String appProjectsDir, String relativePath) =>
      '$appProjectsDir|$relativePath';

  void evictCustomIconCache({
    required String appProjectsDir,
    required String relativePath,
  }) {
    _bytesCache.remove(_cacheKey(appProjectsDir, relativePath));
  }

  void evictProjectCustomIcons({
    required String appProjectsDir,
    required String projectId,
    ProjectIconRef? icon,
  }) {
    if (icon case ProjectIconCustom(:final relativePath) when relativePath.isNotEmpty) {
      evictCustomIconCache(
        appProjectsDir: appProjectsDir,
        relativePath: relativePath,
      );
    }
    _bytesCache.removeWhere(
      (key, _) => key.startsWith('$appProjectsDir|icons/$projectId.'),
    );
  }

  Future<List<int>?> loadCustomBytes({
    required String appProjectsDir,
    required String relativePath,
  }) async {
    final cacheKey = _cacheKey(appProjectsDir, relativePath);
    final cached = _bytesCache[cacheKey];
    if (cached != null) return cached;

    final bytes = await _storage.readBytes(
      appProjectsDir: appProjectsDir,
      relativePath: relativePath,
    );
    if (bytes == null || bytes.isEmpty) return null;
    _bytesCache[cacheKey] = bytes;
    return bytes;
  }

  Future<ProjectIconCustom> importCustomFromLocalFile({
    required String appProjectsDir,
    required String projectId,
    required String localSourcePath,
  }) async {
    final ext = _extension(localSourcePath);
    if (!ProjectIconStorage.isAllowedExtension(ext)) {
      throw ProjectIconImportException('Unsupported file type: .$ext');
    }

    final bytes = await File(localSourcePath).readAsBytes();
    if (bytes.isEmpty) {
      throw ProjectIconImportException('Icon file is empty');
    }

    final relativePath = await _storage.saveBytes(
      appProjectsDir: appProjectsDir,
      projectId: projectId,
      bytes: bytes,
      extension: ext,
    );
    if (relativePath == null) {
      throw ProjectIconImportException('Could not save icon file');
    }

    evictProjectCustomIcons(
      appProjectsDir: appProjectsDir,
      projectId: projectId,
    );
    return ProjectIconCustom(relativePath);
  }

  Future<void> deleteCustomFilesForTransition({
    required String appProjectsDir,
    required String projectId,
    required ProjectIconRef previous,
    required ProjectIconRef next,
  }) async {
    if (previous is! ProjectIconCustom || !previous.isValid) return;
    if (next is ProjectIconCustom && next.relativePath == previous.relativePath) {
      return;
    }
    await _storage.deleteFile(
      appProjectsDir: appProjectsDir,
      relativePath: previous.relativePath,
    );
    evictCustomIconCache(
      appProjectsDir: appProjectsDir,
      relativePath: previous.relativePath,
    );
  }

  Future<void> deleteAllCustomFilesForProject({
    required String appProjectsDir,
    required String projectId,
    ProjectIconRef? icon,
  }) async {
    if (icon case ProjectIconCustom(:final relativePath) when relativePath.isNotEmpty) {
      await _storage.deleteFile(
        appProjectsDir: appProjectsDir,
        relativePath: relativePath,
      );
    }
    await _storage.deleteAllForProject(
      appProjectsDir: appProjectsDir,
      projectId: projectId,
    );
    evictProjectCustomIcons(
      appProjectsDir: appProjectsDir,
      projectId: projectId,
      icon: icon,
    );
  }

  String _extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return '';
    return path.substring(dot + 1).toLowerCase();
  }
}

class ProjectIconImportException implements Exception {
  ProjectIconImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Shared instance for UI reads; repositories may construct their own for tests.
ProjectIconService projectIconService = ProjectIconService();
