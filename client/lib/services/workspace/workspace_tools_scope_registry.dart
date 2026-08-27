import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/session/session_lifecycle_service.dart';
import 'workspace_tools_scope.dart';

/// Retains resolved [WorkspaceToolsScopeCubit]s per title-bar tab scope so
/// returning to a workspace tab keeps the tools plane (file tree, git) visible
/// while a background re-sync runs.
/// Notifies listeners whenever a scope cubit is registered or removed, so
/// late consumers (e.g. the floating-workspace scope bridge) can re-resolve
/// without waiting for an unrelated rebuild. Announcements are deferred out of
/// the build phase, so a registration performed from a widget build (e.g.
/// [WorkspaceSplitPaneState] resolving its scope cubit) never triggers
/// markNeedsBuild on a peer listener.
class WorkspaceToolsScopeRegistry extends ChangeNotifier {
  final Map<String, WorkspaceToolsScopeCubit> _cubits =
      <String, WorkspaceToolsScopeCubit>{};
  bool _notifyScheduled = false;
  bool _isDisposed = false;

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
    _scheduleNotify();
    return cubit;
  }

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
    _scheduleNotify();
  }

  /// Defers announcements until after the current frame's build phase, so a
  /// registration from a widget build (e.g. WorkspaceSplitPane resolving its
  /// scope cubit) never marks a peer ListenableBuilder (e.g. the
  /// floating-workspace scope bridge) dirty while the framework is building.
  /// Coalesces multiple mutations within the same frame; still fires in the
  /// same microtask so late consumers re-resolve promptly.
  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (_isDisposed) return;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    for (final cubit in _cubits.values) {
      cubit.close();
    }
    _cubits.clear();
    super.dispose();
  }
}
