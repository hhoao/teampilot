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

  bool _rowResizing = false;
  bool _rootResizing = false;

  /// When narrow, the side regions render as overlays (see [PaneOverlayHost]),
  /// so the docked panes render nothing for left/right to avoid double-mounting
  /// the sidebar / right-tools panel. Set each build before the pane builders
  /// run (during layout of the root `MultiPane`).
  bool _narrow = false;

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

  // --- Prefs/effective → controllers (post-frame, never during build) -------

  void _scheduleSync(WorkspaceIdePaneSnapshot snapshot) {
    if (_sameAsApplied(snapshot)) return;
    _pending = snapshot;
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      final pending = _pending;
      if (!mounted || pending == null) return;
      _applySnapshot(pending);
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

  Widget _rowPaneBuilder(BuildContext context, String id, double progress) {
    return switch (id) {
      _leftId => _narrow
          ? const SizedBox.shrink()
          : WorkspaceIdePaneChrome(child: widget.left),
      _rightId => _narrow
          ? const SizedBox.shrink()
          : WorkspaceIdePaneChrome(child: widget.right),
      _ => WorkspaceIdePaneChrome(child: widget.center),
    };
  }

  Widget _rootPaneBuilder(BuildContext context, String id, double progress) {
    if (id == _bottomId) {
      return WorkspaceIdePaneChrome(child: widget.bottom);
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
    return BlocBuilder<LayoutCubit, LayoutState>(
      buildWhen: (a, b) => _relevantPrefsChanged(a.preferences, b.preferences),
      builder: (context, layoutState) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final effective = WorkspacePanePolicy.effective(
              preferences: layoutState.preferences,
              viewportWidth: constraints.maxWidth,
            );
            final snapshot = WorkspaceIdePaneSnapshot.from(
              preferences: layoutState.preferences,
              effective: effective,
            );
            _scheduleSync(snapshot);
            // Set before building `MultiPane`: the pane builders run during the
            // root pane's layout, which is after this synchronous assignment.
            _narrow = effective.isNarrow;
            final prefs = layoutState.preferences;
            return PaneTheme(
              data: workspaceIdePaneTheme(cs),
              child: Padding(
                padding: const EdgeInsets.all(WorkspaceIdePaneChrome.shellGutter),
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
