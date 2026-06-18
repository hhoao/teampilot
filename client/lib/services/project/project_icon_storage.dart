import 'package:path/path.dart' as p;

import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Low-level IO for workspace icon files under `{workspaceDir}/assets/icon.*`.
class WorkspaceIconStorage {
  WorkspaceIconStorage({Filesystem? filesystem})
    : _filesystem = filesystem ?? AppStorage.fs;

  final Filesystem _filesystem;

  static const assetsDirName = 'assets';
  static const iconBaseName = 'icon';
  static const allowedExtensions = {'png', 'jpg', 'jpeg', 'webp', 'svg'};

  static String relativeIconPath(String extension) {
    final ext = extension.toLowerCase();
    return p.posix.join(assetsDirName, '$iconBaseName.$ext');
  }

  static String? absoluteIconPath(String workspaceDir, String relativePath) {
    if (relativePath.trim().isEmpty) return null;
    final ctx = AppPaths.pathContextForDataRoot(workspaceDir);
    return ctx.join(workspaceDir, relativePath.replaceAll(r'\', '/'));
  }

  static bool isSvgPath(String relativePath) =>
      relativePath.toLowerCase().endsWith('.svg');

  static bool isAllowedExtension(String extension) {
    return allowedExtensions.contains(extension.toLowerCase());
  }

  Future<String?> saveBytes({
    required String workspaceDir,
    required String workspaceId,
    required List<int> bytes,
    required String extension,
  }) async {
    if (bytes.isEmpty || !isAllowedExtension(extension)) return null;

    final relativePath = relativeIconPath(extension);
    final absolutePath = absoluteIconPath(workspaceDir, relativePath);
    if (absolutePath == null) return null;

    final ctx = AppPaths.pathContextForDataRoot(workspaceDir);
    await _filesystem.ensureDir(ctx.join(workspaceDir, assetsDirName));
    await deleteAllForWorkspace(workspaceDir: workspaceDir, workspaceId: workspaceId);
    await _filesystem.writeBytes(absolutePath, bytes);
    return relativePath;
  }

  Future<List<int>?> readBytes({
    required String workspaceDir,
    required String relativePath,
  }) async {
    final absolutePath = absoluteIconPath(workspaceDir, relativePath);
    if (absolutePath == null) return null;
    return _filesystem.readBytes(absolutePath);
  }

  Future<void> deleteFile({
    required String workspaceDir,
    required String relativePath,
  }) async {
    final absolutePath = absoluteIconPath(workspaceDir, relativePath);
    if (absolutePath == null) return;
    final stat = await _filesystem.stat(absolutePath);
    if (!stat.exists) return;
    await _filesystem.removeRecursive(absolutePath);
  }

  Future<void> deleteAllForWorkspace({
    required String workspaceDir,
    required String workspaceId,
  }) async {
    final ctx = AppPaths.pathContextForDataRoot(workspaceDir);
    final assetsDir = ctx.join(workspaceDir, assetsDirName);
    final stat = await _filesystem.stat(assetsDir);
    if (!stat.isDirectory) return;

    for (final entry in await _filesystem.listDir(assetsDir)) {
      if (entry.isDirectory) continue;
      if (!entry.name.startsWith('$iconBaseName.')) continue;
      await _filesystem.removeRecursive(ctx.join(assetsDir, entry.name));
    }
  }
}
