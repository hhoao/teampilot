import '../io/filesystem.dart';

/// A file whose name matched a workspace search query.
class WorkspaceFileMatch {
  const WorkspaceFileMatch({
    required this.path,
    required this.name,
    required this.relativePath,
  });

  /// Absolute path to the matched file.
  final String path;

  /// File name (basename), the part matched against the query.
  final String name;

  /// Path relative to the search root, shown as the result subtitle.
  final String relativePath;
}

/// Outcome of [searchWorkspaceFiles]: the capped result list and whether the
/// search stopped early because [WorkspaceFileSearchLimits.maxResults] was hit.
class WorkspaceFileSearchResult {
  const WorkspaceFileSearchResult({
    required this.matches,
    required this.truncated,
  });

  const WorkspaceFileSearchResult.empty()
    : matches = const [],
      truncated = false;

  final List<WorkspaceFileMatch> matches;
  final bool truncated;
}

/// Tuning knobs for [searchWorkspaceFiles].
class WorkspaceFileSearchLimits {
  const WorkspaceFileSearchLimits({
    this.maxResults = 50,
    this.maxEntriesScanned = 20000,
  });

  /// Stop after collecting this many matches (sets `truncated`).
  final int maxResults;

  /// Hard ceiling on entries visited so a huge tree can't hang the search.
  final int maxEntriesScanned;
}

/// Directory names skipped wholesale during traversal.
const _ignoredDirNames = {
  '.git',
  '.hg',
  '.svn',
  'node_modules',
  '.dart_tool',
  'build',
  '.idea',
  '.gradle',
  '.next',
  'dist',
};

/// Recursively searches [root] for files whose name contains [query]
/// (case-insensitive), breadth-first so shallow matches surface first.
///
/// Hidden entries (names starting with `.`) and common build/VCS directories
/// are skipped. Unreadable directories are silently ignored. Pure and
/// filesystem-injected so it is unit-testable.
Future<WorkspaceFileSearchResult> searchWorkspaceFiles({
  required Filesystem fs,
  required String root,
  required String query,
  WorkspaceFileSearchLimits limits = const WorkspaceFileSearchLimits(),
}) async {
  final q = query.trim().toLowerCase();
  if (root.isEmpty || q.isEmpty) return const WorkspaceFileSearchResult.empty();

  final ctx = fs.pathContext;
  final matches = <WorkspaceFileMatch>[];
  final queue = <String>[root];
  var scanned = 0;
  var truncated = false;

  while (queue.isNotEmpty && scanned < limits.maxEntriesScanned) {
    final dir = queue.removeAt(0);
    List<FsDirEntry> entries;
    try {
      entries = await fs.listDir(dir);
    } catch (_) {
      continue;
    }
    for (final entry in entries) {
      scanned++;
      if (entry.name.startsWith('.')) continue;
      final full = ctx.join(dir, entry.name);
      if (entry.isDirectory) {
        if (_ignoredDirNames.contains(entry.name)) continue;
        queue.add(full);
        continue;
      }
      if (!entry.name.toLowerCase().contains(q)) continue;
      matches.add(
        WorkspaceFileMatch(
          path: full,
          name: entry.name,
          relativePath: ctx.relative(full, from: root),
        ),
      );
      if (matches.length >= limits.maxResults) {
        truncated = true;
        return WorkspaceFileSearchResult(matches: matches, truncated: truncated);
      }
    }
  }

  return WorkspaceFileSearchResult(matches: matches, truncated: truncated);
}
