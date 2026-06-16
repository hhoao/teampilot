import 'package:path/path.dart' as p;

import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Low-level IO for project icon files under `{projectDir}/assets/icon.*`.
class ProjectIconStorage {
  ProjectIconStorage({Filesystem? filesystem})
    : _filesystem = filesystem ?? AppStorage.fs;

  final Filesystem _filesystem;

  static const assetsDirName = 'assets';
  static const iconBaseName = 'icon';
  static const allowedExtensions = {'png', 'jpg', 'jpeg', 'webp', 'svg'};

  static String relativeIconPath(String extension) {
    final ext = extension.toLowerCase();
    return p.posix.join(assetsDirName, '$iconBaseName.$ext');
  }

  static String? absoluteIconPath(String projectDir, String relativePath) {
    if (relativePath.trim().isEmpty) return null;
    final ctx = AppPaths.pathContextForDataRoot(projectDir);
    return ctx.join(projectDir, relativePath.replaceAll(r'\', '/'));
  }

  static bool isSvgPath(String relativePath) =>
      relativePath.toLowerCase().endsWith('.svg');

  static bool isAllowedExtension(String extension) {
    return allowedExtensions.contains(extension.toLowerCase());
  }

  Future<String?> saveBytes({
    required String projectDir,
    required String projectId,
    required List<int> bytes,
    required String extension,
  }) async {
    if (bytes.isEmpty || !isAllowedExtension(extension)) return null;

    final relativePath = relativeIconPath(extension);
    final absolutePath = absoluteIconPath(projectDir, relativePath);
    if (absolutePath == null) return null;

    final ctx = AppPaths.pathContextForDataRoot(projectDir);
    await _filesystem.ensureDir(ctx.join(projectDir, assetsDirName));
    await deleteAllForProject(projectDir: projectDir, projectId: projectId);
    await _filesystem.writeBytes(absolutePath, bytes);
    return relativePath;
  }

  Future<List<int>?> readBytes({
    required String projectDir,
    required String relativePath,
  }) async {
    final absolutePath = absoluteIconPath(projectDir, relativePath);
    if (absolutePath == null) return null;
    return _filesystem.readBytes(absolutePath);
  }

  Future<void> deleteFile({
    required String projectDir,
    required String relativePath,
  }) async {
    final absolutePath = absoluteIconPath(projectDir, relativePath);
    if (absolutePath == null) return;
    final stat = await _filesystem.stat(absolutePath);
    if (!stat.exists) return;
    await _filesystem.removeRecursive(absolutePath);
  }

  Future<void> deleteAllForProject({
    required String projectDir,
    required String projectId,
  }) async {
    final ctx = AppPaths.pathContextForDataRoot(projectDir);
    final assetsDir = ctx.join(projectDir, assetsDirName);
    final stat = await _filesystem.stat(assetsDir);
    if (!stat.isDirectory) return;

    for (final entry in await _filesystem.listDir(assetsDir)) {
      if (entry.isDirectory) continue;
      if (!entry.name.startsWith('$iconBaseName.')) continue;
      await _filesystem.removeRecursive(ctx.join(assetsDir, entry.name));
    }
  }
}
