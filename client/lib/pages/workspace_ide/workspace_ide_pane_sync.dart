import '../../models/layout_preferences.dart';
import '../../services/workspace/workspace_pane_policy.dart';

/// Desired pane sizes and dock/overlay flags for [WorkspaceIdeShell],
/// derived from prefs intent + the current [WorkspacePaneEffective].
///
/// Pure data: no `panes` / Flutter imports. The shell applies this to its
/// `PaneController`s; drag-end writes go back through [LayoutCubit]
/// via [WorkspaceIdePendingDrag], not through this snapshot.
class WorkspaceIdePaneSnapshot {
  const WorkspaceIdePaneSnapshot({
    required this.isNarrow,
    required this.dockLeft,
    required this.dockRight,
    required this.overlayLeft,
    required this.overlayRight,
    required this.intentSidebarVisible,
    required this.intentRightToolsVisible,
    required this.sidebarWidth,
    required this.rightToolsWidth,
  });

  factory WorkspaceIdePaneSnapshot.from({
    required LayoutPreferences preferences,
    required WorkspacePaneEffective effective,
  }) {
    return WorkspaceIdePaneSnapshot(
      isNarrow: effective.isNarrow,
      dockLeft: effective.dockLeft,
      dockRight: effective.dockRight,
      overlayLeft: effective.overlayLeft,
      overlayRight: effective.overlayRight,
      intentSidebarVisible: preferences.sidebarVisible,
      intentRightToolsVisible: preferences.rightToolsVisible,
      sidebarWidth: preferences.sidebarWidth,
      rightToolsWidth: preferences.rightToolsWidth,
    );
  }

  final bool isNarrow;
  final bool dockLeft;
  final bool dockRight;
  final bool overlayLeft;
  final bool overlayRight;

  final bool intentSidebarVisible;
  final bool intentRightToolsVisible;

  final double sidebarWidth;
  final double rightToolsWidth;
}

/// Dynamic max extents for side panes so the main workbench keeps
/// [LayoutPreferences.minWorkbenchMainWidth] / [minWorkbenchMainHeight].
///
/// Side panes no longer have a hard global max; these caps are derived from the
/// current viewport and the opposite pane so the center cannot be crushed to 0.
class WorkspaceIdePaneBounds {
  const WorkspaceIdePaneBounds({
    required this.leftMax,
    required this.rightMax,
  });

  /// Keep aligned with [WorkspaceIdePaneChrome.resizerThickness].
  static const double resizerThickness = 1.0;

  /// Keep aligned with [WorkspaceIdePaneChrome.shellGutter].
  static const double shellGutter = 8.0;

  final double leftMax;
  final double rightMax;

  /// [availableWidth] is the MultiPane host width after shell gutters
  /// (see [shellAvailableSize]).
  factory WorkspaceIdePaneBounds.compute({
    required double availableWidth,
    required bool dockLeft,
    required bool dockRight,
    required double sidebarWidth,
    required double rightToolsWidth,
  }) {
    final leftTaken = dockLeft ? sidebarWidth : 0.0;
    final rightTaken = dockRight ? rightToolsWidth : 0.0;
    final rowResizers = switch ((dockLeft, dockRight)) {
      (true, true) => 2,
      (true, false) || (false, true) => 1,
      (false, false) => 0,
    };
    final rowResizerSpace = rowResizers * resizerThickness;

    return WorkspaceIdePaneBounds(
      leftMax: _atLeast(
        availableWidth -
            rightTaken -
            LayoutPreferences.minWorkbenchMainWidth -
            rowResizerSpace,
        LayoutPreferences.minSidebarWidth,
      ),
      rightMax: _atLeast(
        availableWidth -
            leftTaken -
            LayoutPreferences.minWorkbenchMainWidth -
            rowResizerSpace,
        LayoutPreferences.minRightToolsWidth,
      ),
    );
  }

  /// Host size for the docked `MultiPane` after shell gutters.
  static ({double width, double height}) shellAvailableSize({
    required double viewportWidth,
    required double viewportHeight,
    required bool dockLeft,
    required bool dockRight,
  }) {
    final horizontal =
        (dockLeft ? shellGutter : 0.0) + (dockRight ? shellGutter : 0.0);
    final vertical = shellGutter * 2;
    return (
      width: viewportWidth - horizontal,
      height: viewportHeight - vertical,
    );
  }

  static double _atLeast(double value, double min) =>
      value < min ? min : value;

  @override
  bool operator ==(Object other) {
    return other is WorkspaceIdePaneBounds &&
        other.leftMax == leftMax &&
        other.rightMax == rightMax;
  }

  @override
  int get hashCode => Object.hash(leftMax, rightMax);
}

/// Which prefs-backed size a [WorkspaceIdePendingDrag] is tracking.
enum WorkspaceIdeDragTarget { sidebar, rightTools }

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
