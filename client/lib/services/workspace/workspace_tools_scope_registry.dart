import '../../services/session/session_lifecycle_service.dart';
import 'workspace_tools_scope.dart';

/// Retains resolved [WorkspaceToolsScopeCubit]s per title-bar tab scope so
/// returning to a workspace tab keeps the tools plane (file tree, git) visible
/// while a background re-sync runs.
class WorkspaceToolsScopeRegistry {
  final Map<String, WorkspaceToolsScopeCubit> _cubits =
      <String, WorkspaceToolsScopeCubit>{};

  WorkspaceToolsScopeCubit cubitFor({
    required String tabScopeId,
    required SessionLifecycleService lifecycle,
  }) {
    final key = tabScopeId.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(tabScopeId, 'tabScopeId', 'must not be empty');
    }
    final existing = _cubits[key];
    if (existing != null && !existing.isClosed) return existing;

    final cubit = WorkspaceToolsScopeCubit(lifecycle: lifecycle);
    _cubits[key] = cubit;
    return cubit;
  }

  void removeScope(String tabScopeId) {
    final key = tabScopeId.trim();
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
