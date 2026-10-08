import '../../services/io/filesystem.dart';
import 'workspace_path_utils.dart';

/// Collects every metadata / trust lookup key for [directories], including git
/// repository roots (Claude Code uses git root in `projects` keys).
Future<Set<String>> collectTrustedProjectKeys({
  required Filesystem fs,
  required bool usesPosixPaths,
  required Iterable<String> directories,
}) async {
  final keys = <String>{};
  for (final directory in directories) {
    final trimmed = directory.trim();
    if (trimmed.isEmpty) continue;
    for (final pathKey in workspaceMetadataKeys(
      trimmed,
      usesPosixPaths: usesPosixPaths,
    )) {
      keys.add(pathKey);
      final gitRoot = await findCanonicalGitRoot(
        fs,
        pathKey,
        usesPosixPaths: usesPosixPaths,
      );
      if (gitRoot != null) {
        keys.addAll(
          workspaceMetadataKeys(gitRoot, usesPosixPaths: usesPosixPaths),
        );
      }
    }
  }
  return keys;
}

/// Walks parents from [startPath] until a `.git` entry exists (file or dir).
Future<String?> findCanonicalGitRoot(
  Filesystem fs,
  String startPath, {
  required bool usesPosixPaths,
}) async {
  var current = normalizeWorkspacePath(
    startPath,
    usesPosixPaths: usesPosixPaths,
  );
  if (current.isEmpty) return null;

  final ctx = fs.pathContext;
  while (true) {
    final gitPath = ctx.join(current, '.git');
    final stat = await fs.stat(gitPath);
    if (stat.exists) {
      return current;
    }
    final parent = ctx.dirname(current);
    if (parent == current) {
      return null;
    }
    current = parent;
  }
}
