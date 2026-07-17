import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:panes/panes.dart';

import '../../cubits/layout_cubit.dart';
import '../../models/layout_preferences.dart';
import '../../services/workspace/workspace_pane_policy.dart';
import '../../widgets/workspace_terminal_panel.dart';
import 'pane_overlay_host.dart';
import 'workspace_ide_pane_chrome.dart';
import 'workspace_ide_pane_sync.dart';

/// App-owned IDE shell that lays out the workspace as left | center | right over
/// a full-bleed bottom terminal, using `panes` as the interaction engine.
///
/// [LayoutCubit] / [LayoutPreferences] stay the sole source of layout intent:
/// the `panes` controllers are derived from prefs on build, and drag-end sizes
/// are committed back through the cubit (never mid-drag — see the design spec's
/// write-back rules). Side / bottom panes use [PaneSize.pixel] so hiding them
/// keeps their child `State` mounted (fractional hide disposes children), which
/// is what protects the bottom PTY and center agent terminals from teardown when
/// a sibling pane toggles.
class WorkspaceIdeShell extends StatefulWidget {
  const WorkspaceIdeShell({
    required this.left,
    required this.center,
    required this.right,
    required this.bottom,
    this.composeLanding = false,
    this.terminalHold,
    super.key,
  });

  final Widget left;
  final Widget center;
  final Widget right;

  /// The bottom workspace terminal. Callers must give it a stable, workspace
  /// scoped [ValueKey] (`workspace-terminal-<id>`) so it survives pane toggles.
  final Widget bottom;

  /// When true, right-tools visibility follows landing override policy instead
  /// of persisted [LayoutPreferences.rightToolsVisible].
  final bool composeLanding;

  /// Bridge used to bracket PTY resizes of [bottom] during a split drag.
  final WorkspaceTerminalHoldHandle? terminalHold;

  @override
  State<WorkspaceIdeShell> createState() => _WorkspaceIdeShellState();
}

class _WorkspaceIdeShellState extends State<WorkspaceIdeShell> {
  static const _leftId = 'left';
  static const _centerId = 'center';
  static const _rightId = 'right';
  static const _mainRowId = 'mainRow';
  static const _bottomId = 'bottom';

  late final PaneController _rowController;
  late final PaneController _rootController;

  WorkspaceIdePaneSnapshot? _applied;
  bool _syncScheduled = false;
  WorkspaceIdePaneSnapshot? _pending;

  /// Last viewport size from [PaneSizeReporter]; used by [BlocListener] to derive
  /// [WorkspacePanePolicy.effective] before the next layout pass.
  double _viewportWidth = WorkspacePanePolicy.narrowBreakpointWidth;
  double _viewportHeight = 900;

  WorkspaceIdePaneBounds? _appliedBounds;
  bool _boundsSyncScheduled = false;
  WorkspaceIdePaneBounds? _pendingBounds;
  WorkspaceIdePaneSnapshot? _pendingBoundsSnapshot;

  bool _rowResizing = false;
  bool _rootResizing = false;

  /// When narrow, the side regions render as overlays (see [PaneOverlayHost]),
  /// so the docked panes render nothing for left/right to avoid double-mounting
  /// the sidebar / right-tools panel. Set each build before the pane builders
  /// run (during layout of the root `MultiPane`).
  bool _narrow = false;

  /// Effective dock flags from the latest viewport measure. Chrome uses
  /// this instead of [PaneController.isVisible] so padding/radius track user
  /// intent immediately — the controller sync is intentionally post-frame.
  WorkspaceIdePaneSnapshot? _layoutSnapshot;

  /// First open skips pane size tweens so sidebar/terminal do not animate
  /// through dozens of layouts on the landing critical path.
  var _paneAnimationEnabled = false;

  @override
  void initState() {
    super.initState();
    // Seed from compose-aware effective so the first frame matches policy.
    // Seeding only `_applied` (and not PaneEntry.visible) lets `_requestSync`
    // short-circuit while controllers still show persisted right-tools intent.
    final layoutState = context.read<LayoutCubit>().state;
    final prefs = layoutState.preferences;
    final effective = WorkspacePanePolicy.effective(
      preferences: prefs,
      viewportWidth: WorkspacePanePolicy.narrowBreakpointWidth,
      composeLanding: widget.composeLanding,
      landingRightToolsOverride: layoutState.landingRightToolsOverride,
    );
    _rowController = PaneController(
      entries: [
        PaneEntry(
          id: _leftId,
          visible: effective.dockLeft,
          initialSize: PaneSize.pixel(prefs.sidebarWidth),
          minSize: PaneSize.pixel(LayoutPreferences.minSidebarWidth),
        ),
        PaneEntry(
          id: _centerId,
          initialSize: PaneSize.fraction(1),
          minSize: PaneSize.pixel(LayoutPreferences.minWorkbenchMainWidth),
        ),
        PaneEntry(
          id: _rightId,
          visible: effective.dockRight,
          initialSize: PaneSize.pixel(prefs.rightToolsWidth),
          minSize: PaneSize.pixel(LayoutPreferences.minRightToolsWidth),
        ),
      ],
    )..addListener(_onRowChanged);
    _rootController = PaneController(
      entries: [
        PaneEntry(
          id: _mainRowId,
          initialSize: PaneSize.fraction(1),
          minSize: PaneSize.pixel(LayoutPreferences.minWorkbenchMainHeight),
        ),
        PaneEntry(
          id: _bottomId,
          visible: effective.dockBottom,
          initialSize: PaneSize.pixel(prefs.workspaceTerminalHeight),
          minSize: PaneSize.pixel(LayoutPreferences.minWorkspaceTerminalHeight),
        ),
      ],
    )..addListener(_onRootChanged);
    _applied = WorkspaceIdePaneSnapshot.from(
      preferences: prefs,
      effective: effective,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _paneAnimationEnabled) return;
      setState(() => _paneAnimationEnabled = true);
    });
  }

  @override
  void didUpdateWidget(covariant WorkspaceIdeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.composeLanding && !widget.composeLanding) {
      context.read<LayoutCubit>().clearLandingRightToolsOverride();
    }
    if (oldWidget.composeLanding != widget.composeLanding) {
      _requestSync(_snapshotFor(context.read<LayoutCubit>().state.preferences));
    }
  }

  @override
  void dispose() {
    _rowController.removeListener(_onRowChanged);
    _rootController.removeListener(_onRootChanged);
    _rowController.dispose();
    _rootController.dispose();
    super.dispose();
  }

  // --- Drag lifecycle: PTY hold on start, prefs commit on end ---------------

  void _onRowChanged() {
    final resizing = _rowController.isResizing;
    if (resizing == _rowResizing) return;
    _rowResizing = resizing;
    if (resizing) {
      widget.terminalHold?.beginPtyHold();
    } else {
      _commitRowSizes();
      widget.terminalHold?.endPtyHold(flush: true);
    }
  }

  void _onRootChanged() {
    final resizing = _rootController.isResizing;
    if (resizing == _rootResizing) return;
    _rootResizing = resizing;
    if (resizing) {
      widget.terminalHold?.beginPtyHold();
    } else {
      _commitRootSizes();
      widget.terminalHold?.endPtyHold(flush: true);
    }
  }

  void _commitRowSizes() {
    if (!mounted) return;
    final cubit = context.read<LayoutCubit>();
    final left = _rowController.getVisualPixelSize(_leftId);
    if (left != null) cubit.setSidebarWidth(left);
    final right = _rowController.getVisualPixelSize(_rightId);
    if (right != null) cubit.setRightToolsWidth(right);
  }

  void _commitRootSizes() {
    if (!mounted) return;
    final bottom = _rootController.getVisualPixelSize(_bottomId);
    if (bottom != null) {
      context.read<LayoutCubit>().setWorkspaceTerminalHeight(bottom);
    }
  }

  // --- Prefs/effective → controllers ----------------------------------------

  WorkspaceIdePaneSnapshot _snapshotFor(LayoutPreferences preferences) {
    final layoutState = context.read<LayoutCubit>().state;
    return WorkspaceIdePaneSnapshot.from(
      preferences: preferences,
      effective: WorkspacePanePolicy.effective(
        preferences: preferences,
        viewportWidth: _viewportWidth,
        composeLanding: widget.composeLanding,
        landingRightToolsOverride: layoutState.landingRightToolsOverride,
      ),
    );
  }

  bool _isDockOnlyChange(WorkspaceIdePaneSnapshot next) {
    final applied = _applied;
    if (applied == null) return false;
    return applied.sidebarWidth == next.sidebarWidth &&
        applied.rightToolsWidth == next.rightToolsWidth &&
        applied.workspaceTerminalHeight == next.workspaceTerminalHeight &&
        (applied.dockLeft != next.dockLeft ||
            applied.dockRight != next.dockRight ||
            applied.dockBottom != next.dockBottom ||
            applied.isNarrow != next.isNarrow);
  }

  void _onLayoutPreferencesChanged() {
    if (!mounted) return;
    _requestSync(_snapshotFor(context.read<LayoutCubit>().state.preferences));
  }

  void _onViewportSize(Size size) {
    if (!mounted) return;
    if (size.width == _viewportWidth && size.height == _viewportHeight) {
      return;
    }
    final layoutState = context.read<LayoutCubit>().state;
    final was = WorkspacePanePolicy.effective(
      preferences: layoutState.preferences,
      viewportWidth: _viewportWidth,
      composeLanding: widget.composeLanding,
      landingRightToolsOverride: layoutState.landingRightToolsOverride,
    );
    _viewportWidth = size.width;
    _viewportHeight = size.height;
    final now = WorkspacePanePolicy.effective(
      preferences: layoutState.preferences,
      viewportWidth: _viewportWidth,
      composeLanding: widget.composeLanding,
      landingRightToolsOverride: layoutState.landingRightToolsOverride,
    );
    final snapshot = WorkspaceIdePaneSnapshot.from(
      preferences: layoutState.preferences,
      effective: now,
    );
    _layoutSnapshot = snapshot;
    _requestSync(snapshot);
    _requestBoundsSync(snapshot);
    _narrow = now.isNarrow;
    final policyChanged =
        was.isNarrow != now.isNarrow ||
        was.dockLeft != now.dockLeft ||
        was.dockRight != now.dockRight ||
        was.dockBottom != now.dockBottom ||
        was.overlayLeft != now.overlayLeft ||
        was.overlayRight != now.overlayRight;
    if (policyChanged) {
      setState(() {});
    }
  }

  void _requestSync(WorkspaceIdePaneSnapshot snapshot) {
    if (_sameAsApplied(snapshot)) return;
    _pending = snapshot;
    if (_rowController.isResizing || _rootController.isResizing) {
      _scheduleSyncPostFrame();
      return;
    }
    if (_isDockOnlyChange(snapshot)) {
      _applySnapshot(snapshot);
      _pending = null;
      return;
    }
    _scheduleSyncPostFrame();
  }

  void _scheduleSyncPostFrame() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      final pending = _pending;
      if (!mounted || pending == null || _sameAsApplied(pending)) return;
      if (_rowController.isResizing || _rootController.isResizing) {
        _scheduleSyncPostFrame();
        return;
      }
      _applySnapshot(pending);
      _pending = null;
    });
  }

  bool _sameAsApplied(WorkspaceIdePaneSnapshot s) {
    final a = _applied;
    return a != null &&
        a.dockLeft == s.dockLeft &&
        a.dockRight == s.dockRight &&
        a.dockBottom == s.dockBottom &&
        a.sidebarWidth == s.sidebarWidth &&
        a.rightToolsWidth == s.rightToolsWidth &&
        a.workspaceTerminalHeight == s.workspaceTerminalHeight;
  }

  void _applySnapshot(WorkspaceIdePaneSnapshot s) {
    // Never fight an in-progress drag; the drag-end commit will re-derive.
    if (!_rowController.isResizing) {
      _applyPane(_rowController, _leftId, s.sidebarWidth, visible: s.dockLeft);
      _applyPane(
        _rowController,
        _rightId,
        s.rightToolsWidth,
        visible: s.dockRight,
      );
    }
    if (!_rootController.isResizing) {
      _applyPane(
        _rootController,
        _bottomId,
        s.workspaceTerminalHeight,
        visible: s.dockBottom,
      );
    }
    _applied = s;
    // Re-apply viewport caps after prefs sizes so a large persisted width cannot
    // crush the main column when the window is narrower than before.
    if (!_rowController.isResizing && !_rootController.isResizing) {
      _applyPaneBounds(_boundsFor(s), s);
    }
  }

  void _applyPane(
    PaneController controller,
    String id,
    double size, {
    required bool visible,
  }) {
    // ignore: deprecated_member_use
    controller.updateSize(id, PaneSize.pixel(size));
    if (visible) {
      controller.show(id);
    } else {
      controller.hide(id);
    }
  }

  // --- Viewport-derived max sizes (protect main workbench) ------------------

  WorkspaceIdePaneBounds _boundsFor(WorkspaceIdePaneSnapshot snapshot) {
    final available = WorkspaceIdePaneBounds.shellAvailableSize(
      viewportWidth: _viewportWidth,
      viewportHeight: _viewportHeight,
      dockLeft: snapshot.dockLeft,
      dockRight: snapshot.dockRight,
      dockBottom: snapshot.dockBottom,
    );
    return WorkspaceIdePaneBounds.compute(
      availableWidth: available.width,
      availableHeight: available.height,
      dockLeft: snapshot.dockLeft,
      dockRight: snapshot.dockRight,
      dockBottom: snapshot.dockBottom,
      sidebarWidth: snapshot.sidebarWidth,
      rightToolsWidth: snapshot.rightToolsWidth,
    );
  }

  void _requestBoundsSync(WorkspaceIdePaneSnapshot snapshot) {
    final bounds = _boundsFor(snapshot);
    if (bounds == _appliedBounds && !_needsVisualClamp(bounds, snapshot)) {
      return;
    }
    _pendingBounds = bounds;
    _pendingBoundsSnapshot = snapshot;
    _scheduleBoundsSyncPostFrame();
  }

  bool _needsVisualClamp(
    WorkspaceIdePaneBounds bounds,
    WorkspaceIdePaneSnapshot snapshot,
  ) {
    if (snapshot.dockLeft) {
      final visual = _rowController.getVisualPixelSize(_leftId);
      if (visual != null && visual > bounds.leftMax) return true;
    }
    if (snapshot.dockRight) {
      final visual = _rowController.getVisualPixelSize(_rightId);
      if (visual != null && visual > bounds.rightMax) return true;
    }
    if (snapshot.dockBottom) {
      final visual = _rootController.getVisualPixelSize(_bottomId);
      if (visual != null && visual > bounds.bottomMax) return true;
    }
    return false;
  }

  void _scheduleBoundsSyncPostFrame() {
    if (_boundsSyncScheduled) return;
    _boundsSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _boundsSyncScheduled = false;
      final bounds = _pendingBounds;
      final snapshot = _pendingBoundsSnapshot;
      if (!mounted || bounds == null || snapshot == null) return;
      if (_rowController.isResizing || _rootController.isResizing) {
        _scheduleBoundsSyncPostFrame();
        return;
      }
      _applyPaneBounds(bounds, snapshot);
      _pendingBounds = null;
      _pendingBoundsSnapshot = null;
    });
  }

  void _applyPaneBounds(
    WorkspaceIdePaneBounds bounds,
    WorkspaceIdePaneSnapshot snapshot,
  ) {
    _setPixelPaneMax(_rowController, _leftId, bounds.leftMax);
    _setPixelPaneMax(_rowController, _rightId, bounds.rightMax);
    _setPixelPaneMax(_rootController, _bottomId, bounds.bottomMax);
    if (snapshot.dockLeft) {
      _clampVisualPixelSize(_rowController, _leftId, bounds.leftMax);
    }
    if (snapshot.dockRight) {
      _clampVisualPixelSize(_rowController, _rightId, bounds.rightMax);
    }
    if (snapshot.dockBottom) {
      _clampVisualPixelSize(_rootController, _bottomId, bounds.bottomMax);
    }
    _appliedBounds = bounds;
  }

  void _setPixelPaneMax(PaneController controller, String id, double max) {
    final entry = controller.entries.firstWhere((e) => e.id == id);
    final currentMax = switch (entry.maxSize) {
      PaneSizePixel(:final pixels) => pixels,
      _ => null,
    };
    if (currentMax == max) return;
    controller.updatePane(entry.copyWith(maxSize: PaneSize.pixel(max)));
  }

  void _clampVisualPixelSize(
    PaneController controller,
    String id,
    double max,
  ) {
    final visual = controller.getVisualPixelSize(id);
    if (visual == null || visual <= max) return;
    // ignore: deprecated_member_use
    controller.updateSize(id, PaneSize.pixel(max));
  }

  // --- Build ----------------------------------------------------------------

  bool get _leftDocked => _layoutSnapshot?.dockLeft ?? false;

  bool get _rightDocked => _layoutSnapshot?.dockRight ?? false;

  bool get _bottomDocked => _layoutSnapshot?.dockBottom ?? false;

  EdgeInsets _shellPadding() {
    const g = WorkspaceIdePaneChrome.shellGutter;
    return EdgeInsets.fromLTRB(
      _leftDocked ? g : 0,
      g,
      _rightDocked ? g : 0,
      _bottomDocked ? g : 0,
    );
  }

  static BorderRadius _paneRadiusOnly({
    required bool topLeft,
    required bool bottomLeft,
    required bool topRight,
    required bool bottomRight,
  }) {
    const r = Radius.circular(WorkspaceIdePaneChrome.paneRadius);
    return BorderRadius.only(
      topLeft: topLeft ? r : Radius.zero,
      bottomLeft: bottomLeft ? r : Radius.zero,
      topRight: topRight ? r : Radius.zero,
      bottomRight: bottomRight ? r : Radius.zero,
    );
  }

  Widget _sideChrome({
    required Widget child,
    required bool leadingOuter,
    required bool trailingOuter,
  }) {
    const inset = WorkspaceIdePaneChrome.paneInset;
    return WorkspaceIdePaneChrome(
      padding: EdgeInsets.fromLTRB(
        leadingOuter ? inset : 0,
        inset,
        trailingOuter ? inset : 0,
        inset,
      ),
      borderRadius: _paneRadiusOnly(
        topLeft: leadingOuter,
        bottomLeft: leadingOuter,
        topRight: trailingOuter,
        bottomRight: trailingOuter,
      ),
      child: child,
    );
  }

  Widget _centerChrome() {
    const inset = WorkspaceIdePaneChrome.paneInset;
    return WorkspaceIdePaneChrome(
      padding: EdgeInsets.fromLTRB(
        _leftDocked ? inset : 0,
        inset,
        _rightDocked ? inset : 0,
        inset,
      ),
      borderRadius: _paneRadiusOnly(
        topLeft: _leftDocked,
        bottomLeft: _leftDocked,
        topRight: _rightDocked,
        bottomRight: _rightDocked,
      ),
      child: widget.center,
    );
  }

  Widget _rowPaneBuilder(BuildContext context, String id, double progress) {
    return switch (id) {
      _leftId => _narrow
          ? const SizedBox.shrink()
          : !_leftDocked
          ? widget.left
          : _sideChrome(
              child: widget.left,
              leadingOuter: true,
              trailingOuter: false,
            ),
      _rightId => _narrow
          ? const SizedBox.shrink()
          : !_rightDocked
          ? widget.right
          : _sideChrome(
              child: widget.right,
              leadingOuter: false,
              trailingOuter: true,
            ),
      _ => _centerChrome(),
    };
  }

  Widget _bottomChrome() {
    const inset = WorkspaceIdePaneChrome.paneInset;
    return WorkspaceIdePaneChrome(
      padding: EdgeInsets.fromLTRB(
        _leftDocked ? inset : 0,
        inset,
        _rightDocked ? inset : 0,
        inset,
      ),
      borderRadius: _paneRadiusOnly(
        topLeft: false,
        bottomLeft: _leftDocked,
        topRight: false,
        bottomRight: _rightDocked,
      ),
      child: widget.bottom,
    );
  }

  Widget _rootPaneBuilder(BuildContext context, String id, double progress) {
    if (id == _bottomId) {
      // Always mount [bottom] so the workspace PTY survives hide toggles;
      // [PaneController.hide] collapses height while keeping this subtree.
      if (!_bottomDocked) {
        return widget.bottom;
      }
      return _bottomChrome();
    }
    return MultiPane(
      direction: Axis.horizontal,
      controller: _rowController,
      animationDuration: _paneAnimationDuration,
      paneBuilder: _rowPaneBuilder,
    );
  }

  Duration get _paneAnimationDuration => _paneAnimationEnabled
      ? const Duration(milliseconds: 250)
      : Duration.zero;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocListener<LayoutCubit, LayoutState>(
      listenWhen: (a, b) =>
          _relevantPrefsChanged(a.preferences, b.preferences) ||
          a.landingRightToolsOverride != b.landingRightToolsOverride,
      listener: (context, _) => _onLayoutPreferencesChanged(),
      child: BlocBuilder<LayoutCubit, LayoutState>(
        buildWhen: (a, b) =>
            _relevantPrefsChanged(a.preferences, b.preferences) ||
            a.landingRightToolsOverride != b.landingRightToolsOverride,
        builder: (context, layoutState) {
          final effective = WorkspacePanePolicy.effective(
            preferences: layoutState.preferences,
            viewportWidth: _viewportWidth,
            composeLanding: widget.composeLanding,
            landingRightToolsOverride: layoutState.landingRightToolsOverride,
          );
          final snapshot = WorkspaceIdePaneSnapshot.from(
            preferences: layoutState.preferences,
            effective: effective,
          );
          _layoutSnapshot = snapshot;
          _requestSync(snapshot);
          _requestBoundsSync(snapshot);
          // Set before building `MultiPane`: the pane builders run during the
          // root pane's layout, which is after this synchronous assignment.
          _narrow = effective.isNarrow;
          final prefs = layoutState.preferences;
          // Measure via PaneSizeReporter so center/sidebar BUILD stays in the
          // normal build phase — not nested under LayoutBuilder layout.
          return PaneSizeReporter(
            onSize: _onViewportSize,
            child: PaneTheme(
              data: workspaceIdePaneTheme(cs),
              child: PaneOverlayHost(
                showLeft: effective.overlayLeft,
                showRight: effective.overlayRight,
                leftWidth: prefs.sidebarWidth,
                rightWidth: prefs.rightToolsWidth,
                left: WorkspaceIdePaneChrome(child: widget.left),
                right: WorkspaceIdePaneChrome(child: widget.right),
                onDismissLeft: () =>
                    context.read<LayoutCubit>().setSidebarVisible(false),
                onDismissRight: () {
                  final layout = context.read<LayoutCubit>();
                  if (widget.composeLanding) {
                    layout.setLandingRightToolsOverride(false);
                  } else {
                    layout.setRightToolsVisible(false);
                  }
                },
                child: MultiPane(
                  direction: Axis.vertical,
                  controller: _rootController,
                  animationDuration: _paneAnimationDuration,
                  paneBuilder: _rootPaneBuilder,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  bool _relevantPrefsChanged(LayoutPreferences a, LayoutPreferences b) {
    return a.sidebarVisible != b.sidebarVisible ||
        a.rightToolsVisible != b.rightToolsVisible ||
        a.workspaceTerminalVisible != b.workspaceTerminalVisible ||
        a.sidebarWidth != b.sidebarWidth ||
        a.rightToolsWidth != b.rightToolsWidth ||
        a.workspaceTerminalHeight != b.workspaceTerminalHeight;
  }
}
