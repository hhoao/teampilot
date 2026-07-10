import '../../models/layout_preferences.dart';
import '../../services/workspace/workspace_pane_policy.dart';

/// Desired pane sizes and dock/overlay flags for [WorkspaceIdeShell],
/// derived from prefs intent + the current [WorkspacePaneEffective].
///
/// Pure data: no `panes` imports. The shell applies this to its
/// `PaneController`s; drag-end writes go back through [LayoutCubit]
/// via [WorkspaceIdePendingDrag], not through this snapshot.
class WorkspaceIdePaneSnapshot {
  const WorkspaceIdePaneSnapshot({
    required this.isNarrow,
    required this.dockLeft,
    required this.dockRight,
    required this.dockBottom,
    required this.overlayLeft,
    required this.overlayRight,
    required this.intentSidebarVisible,
    required this.intentRightToolsVisible,
    required this.intentTerminalVisible,
    required this.sidebarWidth,
    required this.rightToolsWidth,
    required this.workspaceTerminalHeight,
  });

  factory WorkspaceIdePaneSnapshot.from({
    required LayoutPreferences preferences,
    required WorkspacePaneEffective effective,
  }) {
    return WorkspaceIdePaneSnapshot(
      isNarrow: effective.isNarrow,
      dockLeft: effective.dockLeft,
      dockRight: effective.dockRight,
      dockBottom: effective.dockBottom,
      overlayLeft: effective.overlayLeft,
      overlayRight: effective.overlayRight,
      intentSidebarVisible: preferences.sidebarVisible,
      intentRightToolsVisible: preferences.rightToolsVisible,
      intentTerminalVisible: preferences.workspaceTerminalVisible,
      sidebarWidth: preferences.sidebarWidth,
      rightToolsWidth: preferences.rightToolsWidth,
      workspaceTerminalHeight: preferences.workspaceTerminalHeight,
    );
  }

  final bool isNarrow;
  final bool dockLeft;
  final bool dockRight;
  final bool dockBottom;
  final bool overlayLeft;
  final bool overlayRight;

  final bool intentSidebarVisible;
  final bool intentRightToolsVisible;
  final bool intentTerminalVisible;

  final double sidebarWidth;
  final double rightToolsWidth;
  final double workspaceTerminalHeight;
}

/// Which prefs-backed size a [WorkspaceIdePendingDrag] is tracking.
enum WorkspaceIdeDragTarget { sidebar, rightTools, workspaceTerminal }

/// A size to write back to `LayoutCubit` once a drag ends.
class WorkspaceIdeDragCommit {
  const WorkspaceIdeDragCommit({required this.target, required this.value});

  final WorkspaceIdeDragTarget target;
  final double value;
}

/// Holds the in-progress size for a pane drag so the shell only writes to
/// `LayoutCubit` on drag end, instead of on every intermediate frame.
///
/// No Flutter dependency. Unit-tested helper for drag-end commits; the current
/// [WorkspaceIdeShell] instead listens to `PaneController.isResizing` and reads
/// visual pixel sizes on drag end. Keep this for tests / alternate wiring.
class WorkspaceIdePendingDrag {
  WorkspaceIdeDragTarget? _target;
  double? _value;

  bool get isDragging => _target != null;

  void start(WorkspaceIdeDragTarget target) {
    _target = target;
    _value = null;
  }

  void update(double value) {
    if (_target == null) {
      return;
    }
    _value = value;
  }

  /// Returns the commit for the drag that just ended, or `null` if no drag
  /// was in progress or it never received an update. Resets internal state
  /// either way so a stale commit cannot be reissued.
  WorkspaceIdeDragCommit? end() {
    final target = _target;
    final value = _value;
    _target = null;
    _value = null;
    if (target == null || value == null) {
      return null;
    }
    return WorkspaceIdeDragCommit(target: target, value: value);
  }
}
