import 'package:equatable/equatable.dart';

import 'git_compare.dart';

/// Which git diff a Source Control style diff tab is showing.
enum ScmDiffMode {
  /// Index vs HEAD (`git diff --cached`).
  staged,

  /// Worktree vs index (`git diff`).
  unstaged,

  /// Worktree vs HEAD (uncommitted; Orca "Changes" mode).
  changes,
}

/// Identifies one open diff: the file plus which two revisions it compares.
sealed class DiffIdentity extends Equatable {
  const DiffIdentity();

  String get absolutePath;

  /// Stable workbench tab id / editor bucket map key.
  ///
  /// Paths are normalized to `/` separators so keys stay stable across
  /// platforms (`p.join` yields `\` on Windows).
  String get storageKey;

  /// True when the right-hand side is the on-disk working tree and the user
  /// may edit it in place.
  bool get isWritableWorkingTree;

  /// Inverse of [storageKey]; null when [key] is not a diff storage key.
  static DiffIdentity? parseStorageKey(String key) =>
      _parseScm(key) ?? _parseCompare(key);
}

/// Storage keys use `/` separators so they stay stable across platforms
/// (`p.join` yields `\` on Windows).
String _keyPath(String path) => path.replaceAll('\\', '/');

final class ScmDiffIdentity extends DiffIdentity {
  const ScmDiffIdentity(this.absolutePath, this.mode);

  @override
  final String absolutePath;

  final ScmDiffMode mode;

  @override
  String get storageKey => '${_keyPath(absolutePath)}::scm.${mode.name}';

  @override
  bool get isWritableWorkingTree => mode == ScmDiffMode.unstaged;

  @override
  List<Object?> get props => [absolutePath, mode];
}

final class CompareDiffIdentity extends DiffIdentity {
  const CompareDiffIdentity({
    required this.absolutePath,
    required this.repoRoot,
    required this.left,
    required this.right,
  });

  @override
  final String absolutePath;

  final String repoRoot;
  final GitCompareSide left;
  final GitCompareSide right;

  @override
  String get storageKey =>
      '${_keyPath(absolutePath)}::compare:${_keyPath(repoRoot)}'
      '|${left.idKey}|${right.idKey}';

  @override
  bool get isWritableWorkingTree => false;

  @override
  List<Object?> get props => [absolutePath, repoRoot, left, right];
}

ScmDiffIdentity? _parseScm(String key) {
  for (final mode in ScmDiffMode.values) {
    final suffix = '::scm.${mode.name}';
    if (!key.endsWith(suffix)) continue;
    final path = key.substring(0, key.length - suffix.length);
    if (path.isEmpty) return null;
    return ScmDiffIdentity(path, mode);
  }
  return null;
}

CompareDiffIdentity? _parseCompare(String key) {
  const marker = '::compare:';
  final markerAt = key.lastIndexOf(marker);
  if (markerAt <= 0) return null;
  final path = key.substring(0, markerAt);
  final payload = key.substring(markerAt + marker.length);

  // Sides are split off from the right so a repo root containing '|' still
  // parses.
  final rightAt = payload.lastIndexOf('|');
  if (rightAt < 0) return null;
  final leftAt = payload.lastIndexOf('|', rightAt - 1);
  if (leftAt < 0) return null;

  final repoRoot = payload.substring(0, leftAt);
  if (repoRoot.isEmpty) return null;
  final left = _parseSide(payload.substring(leftAt + 1, rightAt));
  final right = _parseSide(payload.substring(rightAt + 1));
  if (left == null || right == null) return null;

  return CompareDiffIdentity(
    absolutePath: path,
    repoRoot: repoRoot,
    left: left,
    right: right,
  );
}

GitCompareSide? _parseSide(String idKey) {
  if (idKey == 'wt') return const GitCompareWorkingTree();
  const refPrefix = 'ref:';
  if (idKey.startsWith(refPrefix)) {
    final name = idKey.substring(refPrefix.length);
    if (name.isEmpty) return null;
    return GitCompareRef(name);
  }
  return null;
}
