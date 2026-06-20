import '../../cubits/file_tree_cubit.dart';
import '../storage/app_storage.dart';

/// App-level registry of long-lived [FileTreeCubit]s, one per open workspace.
///
/// Switching workspace tabs via GoRouter disposes [WorkspacePage] (and
/// [RightToolsPanel] with it). Keeping each workspace's tree cubit here — keyed
/// by [workspaceId], not repo path — preserves expand/filter/dirCache when the
/// user returns to a tab they already opened. Closed tabs call [removeWorkspace].
class WorkspaceFileTreeStore {
  WorkspaceFileTreeStore({FileTreeCubit Function()? cubitFactory})
    : _cubitFactory = cubitFactory ?? (() => FileTreeCubit(fs: AppStorage.fs));

  final FileTreeCubit Function() _cubitFactory;

  final Map<String, FileTreeCubit> _cubits = <String, FileTreeCubit>{};

  /// Returns the retained cubit for [workspaceId], creating it on first access.
  FileTreeCubit cubitFor(String workspaceId) {
    final key = workspaceId.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(workspaceId, 'workspaceId', 'must not be empty');
    }
    return _cubits.putIfAbsent(key, _cubitFactory);
  }

  /// Drops a workspace's cubit when its editor tab is closed (see [HomeShell]).
  void removeWorkspace(String workspaceId) {
    final key = workspaceId.trim();
    if (key.isEmpty) return;
    _cubits.remove(key)?.close();
  }

  void dispose() {
    for (final cubit in _cubits.values) {
      cubit.close();
    }
    _cubits.clear();
  }
}
