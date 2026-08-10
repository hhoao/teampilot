import 'dart:async';

import 'package:flutter/foundation.dart';

import '../workbench/workbench_cubit.dart';
import 'floating_workspace_cubit.dart';
import 'floating_workspace_state.dart';

/// Subscribes to both change planes that determine floating-tab projections —
/// [FloatingWorkspaceCubit] chrome emits (via [Cubit.stream]) and
/// [WorkbenchCubit] bar emits (tab presence/order/active) — and re-evaluates
/// [project] on every change, notifying listeners only when the projected value
/// actually changes.
///
/// This is the consumer-side projection primitive: derived floating-tab data is
/// never cached on a cubit; each consumer decides what it needs and dedups
/// against its own last value. Rebuild cost for unrelated tab changes is one
/// cheap [project] call (no widget rebuild when the result is unchanged).
///
/// [T] must be `==`-comparable (the file tree uses `String?`). Call [dispose]
/// to unsubscribe.
class FloatingWorkspaceProjection<T> extends ValueNotifier<T> {
  FloatingWorkspaceProjection(
    this._floating,
    this._workbench,
    this._project, {
    required T initial,
  }) : super(initial) {
    _floatingSub = _floating.stream.listen((_) => _recompute());
    _workbenchSub = _workbench.stream.listen((_) => _recompute());
    _recompute();
  }

  final FloatingWorkspaceCubit _floating;
  final WorkbenchCubit _workbench;
  final T Function(FloatingWorkspaceCubit cubit, WorkbenchCubit workbench)
  _project;
  StreamSubscription<FloatingWorkspaceState>? _floatingSub;
  StreamSubscription<WorkbenchState>? _workbenchSub;

  void _recompute() {
    final next = _project(_floating, _workbench);
    if (next == value) return;
    value = next;
  }

  @override
  void dispose() {
    _floatingSub?.cancel();
    _workbenchSub?.cancel();
    _floatingSub = null;
    _workbenchSub = null;
    super.dispose();
  }
}
