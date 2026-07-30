import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/floating_workspace/floating_panel_visibility.dart';
import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/floating_workspace/floating_workspace_state.dart';
import '../../services/terminal/workspace_terminal_registry.dart';

/// While minimized, lights [FloatingWorkspaceCubit.attention] on terminal
/// activity (PTY working / bell). Restores primary focus on minimize.
///
/// Mount under [FloatingWorkspaceHost] so lifecycle follows the overlay.
class FloatingWorkspaceLifecycleBinder extends StatefulWidget {
  const FloatingWorkspaceLifecycleBinder({required this.child, super.key});

  final Widget child;

  @override
  State<FloatingWorkspaceLifecycleBinder> createState() =>
      _FloatingWorkspaceLifecycleBinderState();
}

class _FloatingWorkspaceLifecycleBinderState
    extends State<FloatingWorkspaceLifecycleBinder> {
  StreamSubscription<FloatingWorkspaceState>? _floatingSub;
  FloatingPanelVisibility? _lastVisibility;
  FocusNode? _restoreFocus;

  WorkspaceTerminalGroup? _watchedGroup;
  final List<StreamSubscription<void>> _bellSubs = [];
  Timer? _workingPoll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_floatingSub != null) return;
    final floating = context.read<FloatingWorkspaceCubit>();
    _lastVisibility = floating.state.visibility;
    _floatingSub = floating.stream.listen(_onFloatingState);
    _syncAttentionWatch(floating.state);
  }

  void _onFloatingState(FloatingWorkspaceState state) {
    final prev = _lastVisibility;
    _lastVisibility = state.visibility;

    final opening =
        prev != FloatingPanelVisibility.open &&
        state.visibility == FloatingPanelVisibility.open;
    final minimizing =
        prev == FloatingPanelVisibility.open &&
        state.visibility == FloatingPanelVisibility.minimized;

    if (opening) {
      // Capture before panel autofocus steals it (listener runs sync on emit).
      _restoreFocus = FocusManager.instance.primaryFocus;
    } else if (minimizing) {
      final node = _restoreFocus;
      _restoreFocus = null;
      if (node != null && node.canRequestFocus) {
        node.requestFocus();
      }
    }

    _syncAttentionWatch(state);
  }

  void _syncAttentionWatch(FloatingWorkspaceState state) {
    _clearAttentionWatch();
    if (state.visibility != FloatingPanelVisibility.minimized) return;
    if (!mounted) return;

    final workspaceId = state.activeWorkspaceId.trim();
    if (workspaceId.isEmpty) return;

    final registry = context.read<WorkspaceTerminalRegistry>();
    final group = registry.groupFor(workspaceId);
    _watchedGroup = group;
    group.addListener(_onGroupChanged);
    _attachEntryWatches(group);
    _workingPoll = Timer.periodic(const Duration(milliseconds: 400), (_) {
      _pollWorking(group);
    });
  }

  void _onGroupChanged() {
    final group = _watchedGroup;
    if (group == null) return;
    _detachBellSubs();
    _attachEntryWatches(group);
  }

  void _attachEntryWatches(WorkspaceTerminalGroup group) {
    final floating = context.read<FloatingWorkspaceCubit>();
    for (final entry in group.entries) {
      _bellSubs.add(
        entry.session.engine.bell.listen((_) {
          if (floating.state.visibility == FloatingPanelVisibility.minimized) {
            floating.setAttention(true);
          }
        }),
      );
    }
  }

  void _pollWorking(WorkspaceTerminalGroup group) {
    if (!mounted) return;
    final floating = context.read<FloatingWorkspaceCubit>();
    if (floating.state.visibility != FloatingPanelVisibility.minimized) return;
    for (final entry in group.entries) {
      if (entry.session.activityTracker.isWorking) {
        floating.setAttention(true);
        return;
      }
    }
  }

  void _detachBellSubs() {
    for (final sub in _bellSubs) {
      unawaited(sub.cancel());
    }
    _bellSubs.clear();
  }

  void _clearAttentionWatch() {
    _workingPoll?.cancel();
    _workingPoll = null;
    _detachBellSubs();
    _watchedGroup?.removeListener(_onGroupChanged);
    _watchedGroup = null;
  }

  @override
  void dispose() {
    unawaited(_floatingSub?.cancel());
    _floatingSub = null;
    _clearAttentionWatch();
    _restoreFocus = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
