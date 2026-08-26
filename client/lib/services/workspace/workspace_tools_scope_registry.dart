import 'package:flutter/foundation.dart';

import '../../services/session/session_lifecycle_service.dart';
import 'workspace_tools_scope.dart';

/// Retains resolved [WorkspaceToolsScopeCubit]s per title-bar tab scope so
/// returning to a workspace tab keeps the tools plane (file tree, git) visible
/// while a background re-sync runs.
/// Notifies listeners whenever a scope cubit is registered or removed, so
/// late consumers (e.g. the floating-workspace scope bridge) can re-resolve
/// without waiting for an unrelated rebuild.
class WorkspaceToolsScopeRegistry extends ChangeNotifier {
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
    notifyListeners();
    return cubit;
  }

  /// TEMP-DIAG: 已注册的 scope key 列表（诊断用）。
  List<String> get debugKeys => _cubits.keys.toList(growable: false);

  /// Returns an already-created cubit without allocating a new one.
  WorkspaceToolsScopeCubit? peek(String tabScopeId) {
    final key = tabScopeId.trim();
    if (key.isEmpty) return null;
    final existing = _cubits[key];
    if (existing == null || existing.isClosed) return null;
    return existing;
  }

  void removeScope(String tabScopeId) {
    final key = tabScopeId.trim();
    if (key.isEmpty) return;
    _cubits.remove(key)?.close();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final cubit in _cubits.values) {
      cubit.close();
    }
    _cubits.clear();
    super.dispose();
  }
}
