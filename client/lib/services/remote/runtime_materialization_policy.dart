/// Which files of a CLI tree are materialized onto a remote work machine.
///
/// Remote launches transfer only the active session runtime closure: small,
/// reusable CLI configuration travels, while repository metadata and shared
/// caches stay behind on the control plane (the remote session owns its own
/// cache — see the Codex session-owned `.tmp/plugins` layout).
class RuntimeMaterializationPolicy {
  const RuntimeMaterializationPolicy();

  /// Directory names whose entire subtree never travels to the work machine.
  ///
  /// `.git`/`.hg`/`.svn`: repository metadata — large, host-specific, and
  /// meaningless on the remote side. `.tmp`: per-session scratch caches
  /// (e.g. Codex's shared plugin pool) that the remote launch recreates.
  static const excludedSegments = {'.git', '.hg', '.svn', '.tmp'};

  /// Whether [relativePath] (relative to the materialization root) should be
  /// copied for [tool]. [appToolTree] is true while enumerating app-level
  /// tool defaults (`cli-defaults/<tool>/…`), false for workspace config
  /// (`workspace/workspaces/<id>/config/<tool>/…`).
  bool include({
    required String tool,
    required bool appToolTree,
    required String relativePath,
  }) {
    for (final segment in _segments(relativePath)) {
      if (excludedSegments.contains(segment)) return false;
    }
    return true;
  }

  Iterable<String> _segments(String relativePath) =>
      relativePath.split('/').where((segment) => segment.isNotEmpty);
}
