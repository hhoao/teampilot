import '../../cubits/file_tree_cubit.dart';
import '../io/filesystem.dart';

/// App-level registry of long-lived [FileTreeCubit]s, one per open workspace
/// and storage target.
///
/// Switching workspace tabs via GoRouter disposes [WorkspacePage] (and
/// [RightToolsPanel] with it). Keeping each workspace's tree cubit here — keyed
/// by [workspaceId] + [targetId] — preserves expand/filter/dirCache when the
/// user returns to a tab they already opened. Closed tabs call [removeWorkspace].
class WorkspaceFileTreeStore {
  WorkspaceFileTreeStore({FileTreeCubit Function(Filesystem fs)? cubitFactory})
    : _cubitFactory = cubitFactory ?? ((fs) => FileTreeCubit(fs: fs));

  final FileTreeCubit Function(Filesystem fs) _cubitFactory;

  final Map<String, FileTreeCubit> _cubits = <String, FileTreeCubit>{};

  static String _key(String workspaceId, String targetId) =>
      '${workspaceId.trim()}@${targetId.trim()}';

  /// Store key when a workspace spans multiple machines in one file tree.
  static const mixedTargetId = 'mixed';

  /// Returns the retained cubit for [workspaceId] on [targetId].
  FileTreeCubit cubitFor(
    String workspaceId, {
    required String targetId,
    required Filesystem fs,
  }) {
    final ws = workspaceId.trim();
    if (ws.isEmpty) {
      throw ArgumentError.value(workspaceId, 'workspaceId', 'must not be empty');
    }
    final tid = targetId.trim().isEmpty ? 'local' : targetId.trim();
    final key = _key(ws, tid);
    final existing = _cubits[key];
    if (existing != null) return existing;
    final cubit = _cubitFactory(fs);
    _cubits[key] = cubit;
    return cubit;
  }

  /// Drops the cubit for one workspace + target when switching machines.
  void removeWorkspaceTarget(String workspaceId, String targetId) {
    final key = _key(workspaceId.trim(), targetId.trim());
    _cubits.remove(key)?.close();
  }

  /// Drops all cubits for [workspaceId] when its editor tab is closed.
  void removeWorkspace(String workspaceId) {
    final prefix = '${workspaceId.trim()}@';
    if (prefix == '@') return;
    final keys = _cubits.keys.where((k) => k.startsWith(prefix)).toList();
    for (final key in keys) {
      _cubits.remove(key)?.close();
    }
  }

  void dispose() {
    for (final cubit in _cubits.values) {
      cubit.close();
    }
    _cubits.clear();
  }
}
