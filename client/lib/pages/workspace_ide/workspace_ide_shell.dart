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
    this.terminalHold,
    super.key,
  });

  final Widget left;
  final Widget center;
  final Widget right;

  /// The bottom workspace terminal. Callers must give it a stable, workspace
  /// scoped [ValueKey] (`workspace-terminal-<id>`) so it survives pane toggles.
  final Widget bottom;

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

  /// Last viewport width from [LayoutBuilder]; used by [BlocListener] to derive
  /// [WorkspacePanePolicy.effective] before the next layout pass.
  double _viewportWidth = WorkspacePanePolicy.narrowBreakpointWidth;

  bool _rowResizing = false;
  bool _rootResizing = false;

  /// When narrow, the side regions render as overlays (see [PaneOverlayHost]),
  /// so the docked panes render nothing for left/right to avoid double-mounting
  /// the sidebar / right-tools panel. Set each build before the pane builders
  /// run (during layout of the root `MultiPane`).
  bool _narrow = false;

  /// Effective dock flags from the latest [LayoutBuilder] frame. Chrome uses
  /// this instead of [PaneController.isVisible] so padding/radius track user
  /// intent immediately — the controller sync is intentionally post-frame.
  WorkspaceIdePaneSnapshot? _layoutSnapshot;

  @override
  void initState() {
    super.initState();
    // Seed from current intent so the first frame is already correct on wide
    // desktop layouts (the common case) — narrow correction, if any, lands in
    // the post-frame sync without a persisted flash.
    final prefs = context.read<LayoutCubit>().state.preferences;
    _rowController = PaneController(
      entries: [
        PaneEntry(
          id: _leftId,
          visible: prefs.sidebarVisible,
          initialSize: PaneSize.pixel(prefs.sidebarWidth),
          minSize: PaneSize.pixel(LayoutPreferences.minSidebarWidth),
          maxSize: PaneSize.pixel(LayoutPreferences.maxSidebarWidth),
        ),
        PaneEntry(id: _centerId, initialSize: PaneSize.fraction(1)),
        PaneEntry(
          id: _rightId,
          visible: prefs.rightToolsVisible,
          initialSize: PaneSize.pixel(prefs.rightToolsWidth),
          minSize: PaneSize.pixel(LayoutPreferences.minRightToolsWidth),
          maxSize: PaneSize.pixel(LayoutPreferences.maxRightToolsWidth),
        ),
      ],
    )..addListener(_onRowChanged);
    _rootController = PaneController(
      entries: [
        PaneEntry(id: _mainRowId, initialSize: PaneSize.fraction(1)),
        PaneEntry(
          id: _bottomId,
          visible: prefs.workspaceTerminalVisible,
          initialSize: PaneSize.pixel(prefs.workspaceTerminalHeight),
          minSize: PaneSize.pixel(LayoutPreferences.minWorkspaceTerminalHeight),
          maxSize: PaneSize.pixel(LayoutPreferences.maxWorkspaceTerminalHeight),
        ),
      ],
    )..addListener(_onRootChanged);
    _applied = WorkspaceIdePaneSnapshot.from(
      preferences: prefs,
      effective: WorkspacePanePolicy.effective(
        preferences: prefs,
        viewportWidth: WorkspacePanePolicy.narrowBreakpointWidth,
      ),
    );
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
    return WorkspaceIdePaneSnapshot.from(
      preferences: preferences,
      effective: WorkspacePanePolicy.effective(
        preferences: preferences,
        viewportWidth: _viewportWidth,
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
      paneBuilder: _rowPaneBuilder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocListener<LayoutCubit, LayoutState>(
      listenWhen: (a, b) => _relevantPrefsChanged(a.preferences, b.preferences),
      listener: (context, _) => _onLayoutPreferencesChanged(),
      child: BlocBuilder<LayoutCubit, LayoutState>(
        buildWhen: (a, b) => _relevantPrefsChanged(a.preferences, b.preferences),
        builder: (context, layoutState) {
          return LayoutBuilder(
            builder: (context, constraints) {
              _viewportWidth = constraints.maxWidth;
              final effective = WorkspacePanePolicy.effective(
                preferences: layoutState.preferences,
                viewportWidth: constraints.maxWidth,
              );
              final snapshot = WorkspaceIdePaneSnapshot.from(
                preferences: layoutState.preferences,
                effective: effective,
              );
              _layoutSnapshot = snapshot;
              _requestSync(snapshot);
              // Set before building `MultiPane`: the pane builders run during the
              // root pane's layout, which is after this synchronous assignment.
              _narrow = effective.isNarrow;
              final prefs = layoutState.preferences;
              return PaneTheme(
                data: workspaceIdePaneTheme(cs),
                child: Padding(
                  padding: _shellPadding(),
                  child: PaneOverlayHost(
                    showLeft: effective.overlayLeft,
                    showRight: effective.overlayRight,
                    leftWidth: prefs.sidebarWidth,
                    rightWidth: prefs.rightToolsWidth,
                    left: WorkspaceIdePaneChrome(child: widget.left),
                    right: WorkspaceIdePaneChrome(child: widget.right),
                    onDismissLeft: () =>
                        context.read<LayoutCubit>().setSidebarVisible(false),
                    onDismissRight: () =>
                        context.read<LayoutCubit>().setRightToolsVisible(false),
                    child: MultiPane(
                      direction: Axis.vertical,
                      controller: _rootController,
                      paneBuilder: _rootPaneBuilder,
                    ),
                  ),
                ),
              );
            },
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
