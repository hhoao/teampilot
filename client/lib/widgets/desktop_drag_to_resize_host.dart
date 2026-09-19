import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../services/app/desktop_window_actions.dart';

/// Keeps [DragToResizeArea] in the tree when the window is maximized so the
/// app subtree is not remounted (which would re-run startup work such as the
/// silent app-update check).
///
/// Maximized / fullscreen windows cannot be resized from the edges; pass
/// [expanded] to disable those handles without changing widget identity.
class DesktopDragToResizeHost extends StatelessWidget {
  const DesktopDragToResizeHost({
    super.key,
    required this.child,
    this.expanded = false,
  });

  final Widget child;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return DragToResizeArea(
      enableResizeEdges: expanded ? const <ResizeEdge>[] : null,
      child: child,
    );
  }
}

/// Listens for maximize / fullscreen and wraps [child] in
/// [DesktopDragToResizeHost].
class DesktopDragToResizeScope extends StatefulWidget {
  const DesktopDragToResizeScope({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopDragToResizeScope> createState() =>
      _DesktopDragToResizeScopeState();
}

class _DesktopDragToResizeScopeState extends State<DesktopDragToResizeScope>
    with WindowListener {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_syncExpanded());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncExpanded() async {
    final expanded = await isDesktopWindowExpanded();
    if (!mounted || _expanded == expanded) return;
    setState(() => _expanded = expanded);
  }

  @override
  void onWindowMaximize() => unawaited(_syncExpanded());

  @override
  void onWindowUnmaximize() => unawaited(_syncExpanded());

  @override
  void onWindowEnterFullScreen() => unawaited(_syncExpanded());

  @override
  void onWindowLeaveFullScreen() => unawaited(_syncExpanded());

  @override
  Widget build(BuildContext context) {
    return DesktopDragToResizeHost(expanded: _expanded, child: widget.child);
  }
}
