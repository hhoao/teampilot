import 'package:path/path.dart' as p;

import '../../utils/workspace/workspace_path_utils.dart';
import '../file_tree/workspace_file_search.dart';
import '../io/filesystem.dart';

class ComposeFileCandidate {
  const ComposeFileCandidate({
    required this.relativePath,
    required this.isDirectory,
  });

  final String relativePath;
  final bool isDirectory;

  String get insertText => '@$relativePath';
}

/// Merges a [WorkspaceFileIndex] file-name result set into compose candidates
/// in the same order as [searchComposeFiles] / [searchComposeFilesDeep]:
/// directories first, then files, each group alphabetical (case-insensitive).
/// Directory paths are emitted with a trailing `/` so drilling keeps working.
List<ComposeFileCandidate> mergeComposeCandidates({
  required List<WorkspaceFileMatch> fileMatches,
  required List<String> directoryPaths,
}) {
  final out = <ComposeFileCandidate>[
    for (final dir in directoryPaths)
      ComposeFileCandidate(relativePath: '$dir/', isDirectory: true),
    for (final match in fileMatches)
      ComposeFileCandidate(
        relativePath: match.relativePath.replaceAll(r'\', '/'),
        isDirectory: false,
      ),
  ];
  out.sort((a, b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    return a.relativePath.toLowerCase().compareTo(b.relativePath.toLowerCase());
  });
  return out;
}

Future<List<ComposeFileCandidate>> searchComposeFiles({
  required Filesystem fs,
  required String workspaceRoot,
  required String query,
  int limit = 20,
}) async {
  final root = normalizeWorkspacePath(workspaceRoot).trim();
  if (root.isEmpty) return const [];

  final segments = query
      .split('/')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final filePrefix = segments.isEmpty ? '' : segments.last;
  var dir = root;
  for (var i = 0; i < segments.length - 1; i++) {
    dir = fs.pathContext.join(dir, segments[i]);
  }

  final entries = await _safeListDir(fs, dir);
  if (entries == null) return const [];

  final out = <ComposeFileCandidate>[];
  final relPrefix = segments.length <= 1
      ? ''
      : '${segments.sublist(0, segments.length - 1).join('/')}/';

  for (final entry in entries) {
    if (out.length >= limit) break;
    final name = entry.name;
    if (name.startsWith('.')) continue;
    if (filePrefix.isNotEmpty &&
        !name.toLowerCase().startsWith(filePrefix.toLowerCase())) {
      continue;
    }
    final relativePath = '$relPrefix${entry.isDirectory ? '$name/' : name}';
    out.add(
      ComposeFileCandidate(
        relativePath: relativePath.replaceAll(r'\', '/'),
        isDirectory: entry.isDirectory,
      ),
    );
  }

  out.sort((a, b) {
    if (a.isDirectory != b.isDirectory) {
      return a.isDirectory ? -1 : 1;
    }
    return a.relativePath.toLowerCase().compareTo(b.relativePath.toLowerCase());
  });
  return out;
}

/// Fallback when [query] has no `/` segments: shallow file name search.
Future<List<ComposeFileCandidate>> searchComposeFilesDeep({
  required Filesystem fs,
  required String workspaceRoot,
  required String query,
  int limit = 20,
  int maxDepth = 4,
}) async {
  final root = normalizeWorkspacePath(workspaceRoot).trim();
  if (root.isEmpty) return const [];

  final needle = query.trim().toLowerCase();
  if (needle.contains('/')) {
    return searchComposeFiles(
      fs: fs,
      workspaceRoot: root,
      query: query,
      limit: limit,
    );
  }

  final out = <ComposeFileCandidate>[];
  final ctx = fs.pathContext;

  Future<void> walk(String dir, int depth) async {
    if (out.length >= limit || depth > maxDepth) return;

    final entries = await _safeListDir(fs, dir);
    if (entries == null) return;

    for (final entry in entries) {
      if (out.length >= limit) return;
      final name = entry.name;
      if (name.startsWith('.')) continue;

      final absolute = ctx.join(dir, name);
      final relative = p.relative(absolute, from: root).replaceAll(r'\', '/');
      if (entry.isDirectory) {
        if (needle.isEmpty || name.toLowerCase().contains(needle)) {
          out.add(
            ComposeFileCandidate(relativePath: '$relative/', isDirectory: true),
          );
        }
        await walk(absolute, depth + 1);
      } else if (needle.isEmpty || name.toLowerCase().contains(needle)) {
        out.add(
          ComposeFileCandidate(relativePath: relative, isDirectory: false),
        );
      }
    }
  }

  await walk(root, 0);
  out.sort((a, b) {
    if (a.isDirectory != b.isDirectory) {
      return a.isDirectory ? 1 : -1;
    }
    return a.relativePath.toLowerCase().compareTo(b.relativePath.toLowerCase());
  });
  return out.take(limit).toList();
}

Future<List<FsDirEntry>?> _safeListDir(Filesystem fs, String dir) async {
  try {
    return await fs.listDir(dir);
  } on Object {
    return null;
  }
}
