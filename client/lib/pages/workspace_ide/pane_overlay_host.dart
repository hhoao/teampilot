import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Presents the left / right IDE regions as drawer-like overlays on top of
/// [child] (the docked [WorkspaceIdeShell] pane tree) for narrow layouts.
///
/// The shell keeps center workbench subtrees inside the docked `MultiPane`
/// at all times; only the side regions move here when the viewport collapses
/// below the narrow breakpoint. That means the [left] / [right] widgets are the
/// *only* instances of those regions on narrow (the docked panes render nothing
/// for the sides), so we never double-mount a sidebar or right-tools panel.
///
/// `*Visible` intent maps to "show the overlay" on narrow; dismissing the
/// overlay (scrim tap / back) calls [onDismissLeft] / [onDismissRight], which
/// the shell wires to `LayoutCubit.setSidebarVisible(false)` /
/// `setRightToolsVisible(false)` — matching the old drawer dismiss → hide rule.
class PaneOverlayHost extends StatefulWidget {
  const PaneOverlayHost({
    required this.child,
    required this.leftWidth,
    required this.rightWidth,
    required this.showLeft,
    required this.showRight,
    required this.onDismissLeft,
    required this.onDismissRight,
    this.left,
    this.right,
    super.key,
  });

  /// The docked pane tree (root `MultiPane`) rendered full-bleed underneath.
  final Widget child;

  /// Side region content, presented in the overlay when the matching
  /// `show*` flag is set. Null disables that side entirely.
  final Widget? left;
  final Widget? right;

  final double leftWidth;
  final double rightWidth;

  final bool showLeft;
  final bool showRight;

  final VoidCallback onDismissLeft;
  final VoidCallback onDismissRight;

  @override
  State<PaneOverlayHost> createState() => _PaneOverlayHostState();
}

class _PaneOverlayHostState extends State<PaneOverlayHost>
    with TickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 200);

  late final AnimationController _leftController;
  late final AnimationController _rightController;

  @override
  void initState() {
    super.initState();
    _leftController = AnimationController(
      vsync: this,
      duration: _duration,
      value: widget.showLeft ? 1 : 0,
    )..addStatusListener(_onAnimationStatus);
    _rightController = AnimationController(
      vsync: this,
      duration: _duration,
      value: widget.showRight ? 1 : 0,
    )..addStatusListener(_onAnimationStatus);
  }

  @override
  void didUpdateWidget(covariant PaneOverlayHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(_leftController, widget.showLeft);
    _syncController(_rightController, widget.showRight);
  }

  @override
  void dispose() {
    _leftController.dispose();
    _rightController.dispose();
    super.dispose();
  }

  void _onAnimationStatus(AnimationStatus status) {
    // Unmount the side child once it has fully slid out so a hidden overlay
    // never keeps a duplicate sidebar / right-tools panel alive.
    if (status == AnimationStatus.dismissed && mounted) {
      setState(() {});
    }
  }

  void _syncController(AnimationController controller, bool show) {
    if (show) {
      controller.forward();
    } else {
      controller.reverse();
    }
  }

  void _dismissOpenSides() {
    if (widget.showLeft) widget.onDismissLeft();
    if (widget.showRight) widget.onDismissRight();
  }

  bool get _leftMounted =>
      widget.left != null &&
      _leftController.status != AnimationStatus.dismissed;

  bool get _rightMounted =>
      widget.right != null &&
      _rightController.status != AnimationStatus.dismissed;

  @override
  Widget build(BuildContext context) {
    final leftMounted = _leftMounted;
    final rightMounted = _rightMounted;
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (leftMounted || rightMounted)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([_leftController, _rightController]),
              builder: (context, _) {
                final t = math.max(
                  _leftController.value,
                  _rightController.value,
                );
                if (t <= 0) return const SizedBox.shrink();
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _dismissOpenSides,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45 * t),
                  ),
                );
              },
            ),
          ),
        if (leftMounted)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: widget.leftWidth,
            child: _OverlayPanel(
              controller: _leftController,
              fromLeft: true,
              child: widget.left!,
            ),
          ),
        if (rightMounted)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: widget.rightWidth,
            child: _OverlayPanel(
              controller: _rightController,
              fromLeft: false,
              child: widget.right!,
            ),
          ),
      ],
    );
  }
}

class _OverlayPanel extends StatelessWidget {
  const _OverlayPanel({
    required this.controller,
    required this.fromLeft,
    required this.child,
  });

  final AnimationController controller;
  final bool fromLeft;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final slide = Tween<Offset>(
      begin: Offset(fromLeft ? -1 : 1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOutCubic));
    return SlideTransition(
      position: slide,
      child: Material(
        color: cs.surface,
        elevation: 12,
        child: child,
      ),
    );
  }
}
