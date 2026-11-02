import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:teampilot_search/teampilot_search.dart';

import '../io/filesystem.dart';
import '../io/sftp_filesystem.dart';
import 'workspace_file_search.dart';

/// Match mode for [WorkspaceFileIndex.query].
enum WorkspaceFileMatchMode {
  /// VSCode-Quick-Open-style subsequence match, ranked by match quality
  /// (consecutive runs, path/camelCase boundaries, earlier position, shorter
  /// path). Used by the workspace Search dialog.
  fuzzy,

  /// Plain case-insensitive `contains` on the file name. Used by the compose
  /// `@`-mention picker so its suggestion semantics stay unchanged.
  contains,
}

class _ScoredFileMatch {
  const _ScoredFileMatch({required this.score, required this.match});

  final int score;
  final WorkspaceFileMatch match;
}

/// Cached, VSCode-style file name index for one workspace root.
///
/// Builds a flat record of every file under [root] once (streamed/chunked so
/// the UI event loop stays responsive), then serves [query] without walking the
/// tree again. On local roots the index — including its fuzzy scoring, which
/// touches every entry — lives on a worker isolate so a query never stalls
/// frames; elsewhere the entries are kept here and queried in memory.
/// [ensureFresh] rebuilds only when the root's mtime changed since the last
/// build (or, when mtimes are unavailable, after
/// [WorkspaceFileIndex.maxStale] has elapsed), so repeated queries and repeated
/// dialog opens reuse the built index.
///
/// Keeps the same skip rules as [searchWorkspaceFiles] (hidden entries and the
/// `_ignoredDirNames` set), so the dialog and the pure walker agree on what is
/// searchable.
class WorkspaceFileIndex {
  WorkspaceFileIndex({
    required this.root,
    required Filesystem fs,
    WorkspaceFileSearchLimits limits = const WorkspaceFileSearchLimits(),
  }) : _fs = fs,
       _limits = limits;

  /// Absolute search root (a workspace folder).
  final String root;

  final Filesystem _fs;
  final WorkspaceFileSearchLimits _limits;

  /// Entries built so far; `null` until the first [ensureFresh] completes.
  List<WorkspaceFileMatch>? _entries;

  /// Lowercased [WorkspaceFileMatch.relativePath] for each entry, built once so
  /// a query does not re-allocate lowercased copies of every path per keystroke.
  List<String>? _lowerPaths;

  /// Distinct relative directory paths (e.g. `src/utils`) collected during the
  /// same build, used by [queryDirectories] for directory-name matches.
  List<String>? _dirs;
  IsolatedFileIndex? _rust;
  DateTime? _builtRootMtime;
  DateTime? _builtAt;
  Future<void>? _buildInFlight;

  /// After this idle time (mtime unavailable) the index rebuilds on the next
  /// [ensureFresh]. Generous so a stable workspace stays cached across dialog
  /// opens; small enough that a long-lived app eventually picks up new files.
  static const maxStale = Duration(minutes: 5);

  /// True once the index has been built at least once.
  bool get isReady => _rust?.isBuilt == true || _entries != null;

  /// Number of files currently indexed (0 before first build).
  int get size => _rust?.isBuilt == true ? 0 : (_entries?.length ?? 0);

  @visibleForTesting
  bool get usedRustBackend => _rust?.isBuilt == true;

  /// Builds the index if missing or stale. Safe to call concurrently from
  /// multiple queries — concurrent callers share the in-flight build.
  Future<void> ensureFresh() async {
    if (isReady && !(await _isStale())) return;
    final inFlight = _buildInFlight;
    if (inFlight != null) return inFlight;
    final build = _buildIndex();
    _buildInFlight = build;
    try {
      await build;
    } finally {
      _buildInFlight = null;
    }
  }

  /// Drops the built index; the next [ensureFresh] rebuilds.
  void invalidate() {
    _rust?.dispose();
    _rust = null;
    _entries = null;
    _lowerPaths = null;
    _dirs = null;
    _builtRootMtime = null;
    _builtAt = null;
  }

  /// Frees resources held by the index.
  void dispose() => invalidate();

  Future<bool> _isStale() async {
    final built = _builtAt;
    final rootMtime = _builtRootMtime;
    if (rootMtime != null) {
      final current = (await _fs.stat(root)).mtime;
      if (current != null) return !current.isAtSameMomentAs(rootMtime);
      // mtime became unavailable — fall back to the TTL check below.
    }
    return built == null || DateTime.now().difference(built) > maxStale;
  }

  bool _shouldUseRust() {
    if (_fs is SftpFilesystem) return false;
    try {
      return FileSystemEntity.typeSync(root) != FileSystemEntityType.notFound;
    } catch (_) {
      return false;
    }
  }

  Future<void> _buildIndex() async {
    if (_shouldUseRust()) {
      final rust = _rust ?? IsolatedFileIndex();
      try {
        await rust.build(
          root,
          TpFileIndexOptions(
            maxEntries: _limits.maxIndexEntries,
            useGitignore: true,
          ),
        );
        _rust = rust;
        _entries = null;
        _lowerPaths = null;
        _dirs = null;
        _builtAt = DateTime.now();
        _builtRootMtime = (await _fs.stat(root)).mtime;
        return;
      } on Object {
        rust.dispose();
        if (identical(_rust, rust)) _rust = null;
      }
    }
    await _build();
  }

  Future<void> _build() async {
    final ctx = _fs.pathContext;
    final entries = <WorkspaceFileMatch>[];
    final lowerPaths = <String>[];
    final dirs = <String>[];
    // BFS with O(1) pop (List.removeAt(0) is O(n) and would make a large
    // workspace build quadratic).
    final queue = ListQueue<String>()..add(root);
    var scanned = 0;
    var dirsListed = 0;
    final maxEntries = _limits.maxIndexEntries;

    while (queue.isNotEmpty && scanned < maxEntries) {
      final dir = queue.removeFirst();
      List<FsDirEntry> children;
      try {
        children = await _fs.listDir(dir);
      } on Object {
        continue;
      }
      dirsListed++;
      for (final entry in children) {
        scanned++;
        if (entry.name.startsWith('.')) continue;
        final full = ctx.join(dir, entry.name);
        if (entry.isDirectory) {
          if (workspaceFileIgnoredDirNames.contains(entry.name)) continue;
          queue.add(full);
          final relative = ctx.relative(full, from: root);
          if (relative.isNotEmpty) dirs.add(relative);
          continue;
        }
        entries.add(
          WorkspaceFileMatch(
            path: full,
            name: entry.name,
            relativePath: ctx.relative(full, from: root),
          ),
        );
        lowerPaths.add(entries.last.relativePath.toLowerCase());
      }
      // Yield to the event loop every few directories so building a large
      // workspace does not stall the UI.
      if (dirsListed % 16 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    _entries = entries;
    _lowerPaths = lowerPaths;
    _dirs = dirs;
    _builtAt = DateTime.now();
    _builtRootMtime = (await _fs.stat(root)).mtime;
  }

  /// Filters the built index. Empty when the index is not built yet or [query]
  /// is blank. On local roots the work happens on the index's worker isolate.
  Future<List<WorkspaceFileMatch>> query(
    String query, {
    int? limit,
    WorkspaceFileMatchMode mode = WorkspaceFileMatchMode.fuzzy,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final cap = limit ?? _limits.maxResults;
    if (cap <= 0) return const [];

    final rust = _rust;
    if (rust != null && rust.isBuilt) {
      try {
        final hits = await rust.query(
          q,
          mode: mode == WorkspaceFileMatchMode.fuzzy
              ? TpFileMatchMode.fuzzy
              : TpFileMatchMode.contains,
          limit: cap,
        );
        return [
          for (final hit in hits)
            WorkspaceFileMatch(
              path: hit.path,
              name: hit.name,
              relativePath: hit.relativePath,
            ),
        ];
      } on Object {
        // The worker was disposed/rebuilt under us (tab close, storage swap).
        // Treat it like an unbuilt index: the next ensureFresh rebuilds.
        return const [];
      }
    }

    final entries = _entries;
    if (entries == null) return const [];
    if (mode == WorkspaceFileMatchMode.contains) {
      final out = <WorkspaceFileMatch>[];
      for (final match in entries) {
        if (out.length >= cap) break;
        if (!match.name.toLowerCase().contains(q)) continue;
        out.add(match);
      }
      return out;
    }

    final lowerPaths = _lowerPaths;
    final scored = <_ScoredFileMatch>[];
    for (var i = 0; i < entries.length; i++) {
      final match = entries[i];
      final score = fuzzyMatchScorePrepared(
        match.relativePath,
        lowerPaths?[i] ?? match.relativePath.toLowerCase(),
        q,
      );
      if (score < 0) continue;
      scored.add(_ScoredFileMatch(score: score, match: match));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0
          ? byScore
          : a.match.relativePath.compareTo(b.match.relativePath);
    });
    return [for (final s in scored.take(cap)) s.match];
  }

  /// Returns relative directory paths (no trailing slash) whose **basename**
  /// contains [query], case-insensitively. Used by the compose `@`-mention
  /// picker to keep directory-drilling suggestions alongside file matches.
  /// Empty when the index is not built yet or [query] is blank.
  Future<List<String>> queryDirectories(String query, {int limit = 20}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty || limit <= 0) return const [];
    final rust = _rust;
    if (rust != null && rust.isBuilt) {
      try {
        return await rust.queryDirectories(q, limit: limit);
      } on Object {
        return const [];
      }
    }

    final dirs = _dirs;
    if (dirs == null) return const [];
    final out = <String>[];
    for (final dir in dirs) {
      if (out.length >= limit) break;
      final slash = dir.lastIndexOf('/');
      final base = slash < 0 ? dir : dir.substring(slash + 1);
      if (!base.toLowerCase().contains(q)) continue;
      out.add(dir);
    }
    return out;
  }
}

/// VSCode-Quick-Open-style subsequence score for [query] against [text]
/// (a relative file path). Returns a higher score for better matches and -1
/// when [query] is not a subsequence of [text].
///
/// Heuristics, mirroring VSCode's Quick Open ranking:
/// - consecutive query characters in the target are the strongest signal;
/// - a match starting at a path-segment / underscore / dash / dot boundary or
///   a camelCase transition scores higher than a mid-word match;
/// - matches that start earlier in the path beat later ones;
/// - a match inside the basename (and especially a basename prefix) is worth
///   more than a match buried in the directory portion;
/// - a shorter relative path beats a longer one at equal match quality.
int fuzzyMatchScore(String text, String query) =>
    fuzzyMatchScorePrepared(text, text.toLowerCase(), query.toLowerCase());

/// Same as [fuzzyMatchScore] with the lowercased forms supplied by the caller.
///
/// The file index keeps every path lowercased after the build so a query does
/// not re-allocate a lowercased copy of each path on every keystroke. [text]
/// must be the original (case-preserving) path — camelCase boundary bonuses
/// need it.
int fuzzyMatchScorePrepared(String text, String target, String q) {
  if (q.isEmpty) return -1;

  var score = 0;
  var searchFrom = 0;
  var run = 0;
  var previousIndex = -1;

  for (final ch in q.codeUnits) {
    var found = -1;
    for (var i = searchFrom; i < target.length; i++) {
      if (target.codeUnitAt(i) == ch) {
        found = i;
        break;
      }
    }
    if (found < 0) return -1;

    final runBroken = previousIndex >= 0 && found != previousIndex + 1;
    if (!runBroken) {
      run++;
      score += 8 * run; // consecutive run bonus (grows with the run)
    } else {
      run = 1;
      score += _boundaryBonus(text, found);
    }
    score += 1; // base per matched character
    score -= found ~/ 8; // earlier position wins
    previousIndex = found;
    searchFrom = found + 1;
  }

  final slash = text.lastIndexOf('/');
  final base = slash < 0 ? text : text.substring(slash + 1);
  final baseLower = base.toLowerCase();
  if (baseLower.startsWith(q)) score += 20;
  if (baseLower.contains(q)) score += 12;
  score -= text.length ~/ 4; // shorter path preferred
  return score;
}

int _boundaryBonus(String text, int index) {
  if (index <= 0) return 6; // match at the very start of the path
  final prev = text.codeUnitAt(index - 1);
  if (prev == 0x2f || prev == 0x5f || prev == 0x2d || prev == 0x2e) {
    return 6; // after `/`, `_`, `-`, `.`
  }
  final cur = text.codeUnitAt(index);
  final prevChar = String.fromCharCode(prev);
  final curChar = String.fromCharCode(cur);
  final prevUpper =
      prevChar.toUpperCase() == prevChar && prevChar.toLowerCase() != prevChar;
  final curLower =
      curChar.toLowerCase() == curChar && curChar.toUpperCase() != curChar;
  return prevUpper && curLower ? 4 : 0; // camelCase boundary
}

/// App-wide cache of [WorkspaceFileIndex]es keyed by search root, so the Search
/// dialog and the compose `@`-mention picker share one build per workspace.
///
/// Freshness is handled by [WorkspaceFileIndex.ensureFresh] (root mtime + TTL).
/// A deliberate second recursive `FsWatcher` per root is avoided — the file
/// tree already keeps one such watch alive per workspace root (see
/// `WorkspaceFsWatcher`), and on Linux each watched subdirectory consumes an
/// inotify descriptor. Callers that know a tree changed (e.g. a file-tree
/// refresh) can call [invalidate] / [remove].
class WorkspaceFileIndexRegistry {
  final Map<String, WorkspaceFileIndex> _byRoot = {};

  /// Returns the shared index for [root], creating it lazily. Subsequent calls
  /// (from any surface) reuse the same built index.
  WorkspaceFileIndex indexFor(String root, Filesystem fs) {
    final key = root.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(root, 'root', 'must not be empty');
    }
    return _byRoot.putIfAbsent(
      key,
      () => WorkspaceFileIndex(root: key, fs: fs),
    );
  }

  /// Drops the index for [root] (e.g. when its workspace tab closes).
  void remove(String root) {
    _byRoot.remove(root.trim())?.dispose();
  }

  /// Drops every index. Call when the home storage backend changes.
  void clear() {
    for (final index in _byRoot.values) {
      index.dispose();
    }
    _byRoot.clear();
  }
}
