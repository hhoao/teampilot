import 'package:path/path.dart' as p;

import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Low-level IO for project icon files under `{appProjectsDir}/icons/`.
class ProjectIconStorage {
  ProjectIconStorage({Filesystem? filesystem})
    : _filesystem = filesystem ?? AppStorage.fs;

  final Filesystem _filesystem;

  static const iconsDirName = 'icons';
  static const allowedExtensions = {'png', 'jpg', 'jpeg', 'webp', 'svg'};

  static String relativeIconPath(String projectId, String extension) {
    final ext = extension.toLowerCase();
    return p.posix.join(iconsDirName, '$projectId.$ext');
  }

  static String? absoluteIconPath(String appProjectsDir, String relativePath) {
    if (relativePath.trim().isEmpty) return null;
    final ctx = AppPaths.pathContextForDataRoot(appProjectsDir);
    return ctx.join(appProjectsDir, relativePath.replaceAll(r'\', '/'));
  }

  static bool isSvgPath(String relativePath) =>
      relativePath.toLowerCase().endsWith('.svg');

  static bool isAllowedExtension(String extension) {
    return allowedExtensions.contains(extension.toLowerCase());
  }

  Future<String?> saveBytes({
    required String appProjectsDir,
    required String projectId,
    required List<int> bytes,
    required String extension,
  }) async {
    if (bytes.isEmpty || !isAllowedExtension(extension)) return null;

    final relativePath = relativeIconPath(projectId, extension);
    final absolutePath = absoluteIconPath(appProjectsDir, relativePath);
    if (absolutePath == null) return null;

    final ctx = AppPaths.pathContextForDataRoot(appProjectsDir);
    await _filesystem.ensureDir(ctx.join(appProjectsDir, iconsDirName));
    await deleteAllForProject(appProjectsDir: appProjectsDir, projectId: projectId);
    await _filesystem.writeBytes(absolutePath, bytes);
    return relativePath;
  }

  Future<List<int>?> readBytes({
    required String appProjectsDir,
    required String relativePath,
  }) async {
    final absolutePath = absoluteIconPath(appProjectsDir, relativePath);
    if (absolutePath == null) return null;
    return _filesystem.readBytes(absolutePath);
  }

  Future<void> deleteFile({
    required String appProjectsDir,
    required String relativePath,
  }) async {
    final absolutePath = absoluteIconPath(appProjectsDir, relativePath);
    if (absolutePath == null) return;
    final stat = await _filesystem.stat(absolutePath);
    if (!stat.exists) return;
    await _filesystem.removeRecursive(absolutePath);
  }

  Future<void> deleteAllForProject({
    required String appProjectsDir,
    required String projectId,
  }) async {
    final ctx = AppPaths.pathContextForDataRoot(appProjectsDir);
    final iconsDir = ctx.join(appProjectsDir, iconsDirName);
    final stat = await _filesystem.stat(iconsDir);
    if (!stat.isDirectory) return;

    for (final entry in await _filesystem.listDir(iconsDir)) {
      if (entry.isDirectory) continue;
      if (!entry.name.startsWith('$projectId.')) continue;
      await _filesystem.removeRecursive(ctx.join(iconsDir, entry.name));
    }
  }
}
