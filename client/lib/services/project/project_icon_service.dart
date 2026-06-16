import 'dart:io';

import '../../models/project_icon_ref.dart';
import 'project_icon_storage.dart';

/// Applies [ProjectIconRef] transitions and loads custom icon bytes with cache.
class ProjectIconService {
  ProjectIconService({ProjectIconStorage? storage})
    : _storage = storage ?? ProjectIconStorage();

  final ProjectIconStorage _storage;
  final _bytesCache = <String, List<int>>{};

  String _cacheKey(String projectDir, String relativePath) =>
      '$projectDir|$relativePath';

  void evictCustomIconCache({
    required String projectDir,
    required String relativePath,
  }) {
    _bytesCache.remove(_cacheKey(projectDir, relativePath));
  }

  void evictProjectCustomIcons({
    required String projectDir,
    required String projectId,
    ProjectIconRef? icon,
  }) {
    if (icon case ProjectIconCustom(:final relativePath) when relativePath.isNotEmpty) {
      evictCustomIconCache(
        projectDir: projectDir,
        relativePath: relativePath,
      );
    }
    _bytesCache.removeWhere(
      (key, _) => key.startsWith('$projectDir|${ProjectIconStorage.assetsDirName}/'),
    );
  }

  Future<List<int>?> loadCustomBytes({
    required String projectDir,
    required String relativePath,
  }) async {
    final cacheKey = _cacheKey(projectDir, relativePath);
    final cached = _bytesCache[cacheKey];
    if (cached != null) return cached;

    final bytes = await _storage.readBytes(
      projectDir: projectDir,
      relativePath: relativePath,
    );
    if (bytes == null || bytes.isEmpty) return null;
    _bytesCache[cacheKey] = bytes;
    return bytes;
  }

  Future<ProjectIconCustom> importCustomFromLocalFile({
    required String projectDir,
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
      projectDir: projectDir,
      projectId: projectId,
      bytes: bytes,
      extension: ext,
    );
    if (relativePath == null) {
      throw ProjectIconImportException('Could not save icon file');
    }

    evictProjectCustomIcons(
      projectDir: projectDir,
      projectId: projectId,
    );
    return ProjectIconCustom(relativePath);
  }

  Future<void> deleteCustomFilesForTransition({
    required String projectDir,
    required String projectId,
    required ProjectIconRef previous,
    required ProjectIconRef next,
  }) async {
    if (previous is! ProjectIconCustom || !previous.isValid) return;
    if (next is ProjectIconCustom && next.relativePath == previous.relativePath) {
      return;
    }
    await _storage.deleteFile(
      projectDir: projectDir,
      relativePath: previous.relativePath,
    );
    evictCustomIconCache(
      projectDir: projectDir,
      relativePath: previous.relativePath,
    );
  }

  Future<void> deleteAllCustomFilesForProject({
    required String projectDir,
    required String projectId,
    ProjectIconRef? icon,
  }) async {
    if (icon case ProjectIconCustom(:final relativePath) when relativePath.isNotEmpty) {
      await _storage.deleteFile(
        projectDir: projectDir,
        relativePath: relativePath,
      );
    }
    await _storage.deleteAllForProject(
      projectDir: projectDir,
      projectId: projectId,
    );
    evictProjectCustomIcons(
      projectDir: projectDir,
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
