import '../../cubits/worktree_cubit.dart';
import 'workspace_worktree_store.dart';

/// Retains long-lived [WorktreeCubit]s per open workspace, backed by
/// [WorkspaceWorktreeStore] for instant hydration on first mount.
class WorkspaceWorktreeRegistry {
  WorkspaceWorktreeRegistry({WorkspaceWorktreeStore? store})
    : _store = store ?? WorkspaceWorktreeStore();

  final WorkspaceWorktreeStore _store;
  final Map<String, WorktreeCubit> _cubits = <String, WorktreeCubit>{};

  WorkspaceWorktreeStore get store => _store;

  WorktreeCubit cubitFor({
    required String workspaceId,
    required String repoPath,
  }) {
    final ws = workspaceId.trim();
    if (ws.isEmpty) {
      throw ArgumentError.value(
        workspaceId,
        'workspaceId',
        'must not be empty',
      );
    }
    final existing = _cubits[ws];
    if (existing != null && !existing.isClosed) return existing;

    final cubit = WorktreeCubit(
      workspaceId: ws,
      worktreeStore: _store,
      initialRepoPath: repoPath,
    );
    _cubits[ws] = cubit;
    return cubit;
  }

  /// Returns an already-created cubit without allocating a new one.
  WorktreeCubit? peek(String workspaceId) {
    final ws = workspaceId.trim();
    if (ws.isEmpty) return null;
    final existing = _cubits[ws];
    if (existing == null || existing.isClosed) return null;
    return existing;
  }

  void removeWorkspace(String workspaceId) {
    final ws = workspaceId.trim();
    if (ws.isEmpty) return;
    _cubits.remove(ws)?.close();
    _store.removeWorkspace(ws);
  }

  void dispose() {
    for (final cubit in _cubits.values) {
      cubit.close();
    }
    _cubits.clear();
    _store.dispose();
  }
}
