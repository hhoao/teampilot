import '../io/filesystem.dart';

class WorkspaceFileLocator {
  const WorkspaceFileLocator();

  Future<String?> locate({
    required String rawPath,
    required Filesystem fs,
    required List<String> searchBases,
  }) async {
    final pathContext = fs.pathContext;
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) return null;

    if (pathContext.isAbsolute(trimmed)) {
      final normalized = pathContext.normalize(trimmed);
      final stat = await fs.stat(normalized);
      return stat.isFile ? normalized : null;
    }

    for (final base in searchBases) {
      final trimmedBase = base.trim();
      if (trimmedBase.isEmpty) continue;
      final normalized = pathContext.normalize(
        pathContext.join(trimmedBase, trimmed),
      );
      final stat = await fs.stat(normalized);
      if (stat.isFile) return normalized;
    }
    return null;
  }
}
