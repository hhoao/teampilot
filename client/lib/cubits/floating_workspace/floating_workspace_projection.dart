import 'dart:async';

import 'package:flutter/foundation.dart';

import 'floating_workspace_cubit.dart';
import 'floating_workspace_state.dart';

/// Subscribes to both [FloatingWorkspaceCubit] change planes — chrome `emit`s
/// (via [Cubit.stream]) and tab-structure mutations ([tabsChanged]) — and
/// re-evaluates [project] on every change, notifying listeners only when the
/// projected value actually changes.
///
/// This is the consumer-side projection primitive: derived tab data is never
/// cached on the cubit; each consumer decides what it needs and dedups against
/// its own last value. Rebuild cost for unrelated tab changes is one cheap
/// [project] call (no widget rebuild when the result is unchanged).
///
/// [T] must be `==`-comparable (the file tree uses `String?`). Call [dispose]
/// to unsubscribe.
class FloatingWorkspaceProjection<T> extends ValueNotifier<T> {
  FloatingWorkspaceProjection(
    this._cubit,
    this._project, {
    required T initial,
  }) : super(initial) {
    _streamSub = _cubit.stream.listen((_) => _recompute());
    _cubit.tabsChanged.addListener(_recompute);
    _recompute();
  }

  final FloatingWorkspaceCubit _cubit;
  final T Function(FloatingWorkspaceCubit cubit) _project;
  StreamSubscription<FloatingWorkspaceState>? _streamSub;

  void _recompute() {
    final next = _project(_cubit);
    if (next == value) return;
    value = next;
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _cubit.tabsChanged.removeListener(_recompute);
    super.dispose();
  }
}
