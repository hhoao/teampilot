import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../cubits/worktree_cubit.dart';
import '../../../models/runtime_target.dart';
import '../../../services/workspace/workspace_tools_scope.dart';
import 'workspace_route_active_scope.dart';

/// Keeps the landing worktree selector's branch labels fresh against terminal /
/// other external git changes while the landing is mounted: reloads the active
/// repo's worktree list on the [refreshInterval] TTL. Skips when not route
/// active, the tools target is remote (SSH/Termux network round-trips), or the
/// compose is submitting/disabled. App-internal mutations are covered by
/// [WorktreeCubit]'s gitMutationSignals subscription, so this is purely the
/// external-change backstop.
class WorkspaceLandingWorktreeRefresher extends StatefulWidget {
  const WorkspaceLandingWorktreeRefresher({
    required this.child,
    this.isSubmitting = false,
    this.disabled = false,
    super.key,
  });

  final Widget child;
  final bool isSubmitting;
  final bool disabled;

  @visibleForTesting
  static const Duration refreshInterval = Duration(seconds: 15);

  @override
  State<WorkspaceLandingWorktreeRefresher> createState() =>
      _WorkspaceLandingWorktreeRefresherState();
}

class _WorkspaceLandingWorktreeRefresherState
    extends State<WorkspaceLandingWorktreeRefresher> {
  Timer? _timer;
  bool _isRemoteTarget = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      WorkspaceLandingWorktreeRefresher.refreshInterval,
      (_) => _tick(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Registering read only here (build phase); the timer callback must not
    // touch dependOnInheritedWidgetOfExactType — cache the target kind instead.
    final tools = WorkspaceToolsScope.maybeOf(context)?.tools;
    _isRemoteTarget =
        tools != null && usesSshTransport(tools.context.target.kind);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final widget = this.widget;
    if (widget.isSubmitting || widget.disabled) return;
    if (!WorkspaceRouteActiveScope.peekRouteActiveOf(context)) return;
    if (_isRemoteTarget) return;

    WorktreeCubit? cubit;
    try {
      cubit = context.read<WorktreeCubit>();
    } on ProviderNotFoundException {
      return;
    }
    if (cubit == null || cubit.state.repoPath.trim().isEmpty) return;
    unawaited(cubit.reloadActiveRepo());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
