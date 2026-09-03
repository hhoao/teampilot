import '../../models/git_graph.dart';

/// Resolves git-compare left-side ref labels from a graph commit row.
///
/// Prefers the first local branch decoration; otherwise uses the full commit
/// hash as [compareRef] and an 8-char prefix (or full hash if shorter) as
/// [titleRef].
({String compareRef, String titleRef}) gitCompareRefsForCommit(
  GitCommitRow row,
) {
  for (final ref in row.refs) {
    if (ref.kind == GitRefDecorationKind.localBranch) {
      return (compareRef: ref.name, titleRef: ref.name);
    }
  }
  final hash = row.hash;
  final short = hash.length <= 8 ? hash : hash.substring(0, 8);
  return (compareRef: hash, titleRef: short);
}
