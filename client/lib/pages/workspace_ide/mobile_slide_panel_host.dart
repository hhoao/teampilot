import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Single start-side slide-in panel + scrim over [child], matching the narrow
/// workspace drawer motion (200ms easeOutCubic, 0.45 max scrim alpha).
///
/// Used by the home library sidebar and composed into
/// [MobileWorkspaceDrawerHost].
class MobileSlidePanelHost extends StatefulWidget {
  const MobileSlidePanelHost({
    required this.child,
    required this.panel,
    required this.width,
    required this.open,
    required this.onDismiss,
    this.scrimKey,
    this.overlayActive = true,
    this.onReleaseOverlayOwnership,
    super.key,
  });

  /// Full-bleed content under the overlay.
  final Widget child;

  /// Panel content (sidebar / drawer shell).
  final Widget panel;

  final double width;
  final bool open;
  final VoidCallback onDismiss;

  /// Optional key for the scrim (tests).
  final Key? scrimKey;

  /// When false, this host does not show the panel even if [open] is true.
  ///
  /// Losing ownership (`true` → `false`) invokes [onReleaseOverlayOwnership]
  /// once (post-frame) so shared open flags (e.g. [TpSidebarScope.openMobile])
  /// can close — same rule as [TpSidebar.overlayActive].
  final bool overlayActive;

  final VoidCallback? onReleaseOverlayOwnership;

  @override
  State<MobileSlidePanelHost> createState() => _MobileSlidePanelHostState();
}

class _MobileSlidePanelHostState extends State<MobileSlidePanelHost>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 200);

  late final AnimationController _controller;

  bool get _effectiveOpen => widget.overlayActive && widget.open;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _duration,
      value: _effectiveOpen ? 1 : 0,
    )..addStatusListener(_onAnimationStatus);
  }

  @override
  void didUpdateWidget(covariant MobileSlidePanelHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.overlayActive && !widget.overlayActive) {
      // Never notify ancestors during build / didUpdateWidget (TpSidebar rule).
      _scheduleReleaseOverlayOwnership();
    }
    if (_effectiveOpen) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _scheduleReleaseOverlayOwnership() {
    final release = widget.onReleaseOverlayOwnership;
    if (release == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.overlayActive) return;
      release();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) {
      setState(() {});
    }
  }

  bool get _panelMounted =>
      _controller.status != AnimationStatus.dismissed;

  @override
  Widget build(BuildContext context) {
    final panelMounted = _panelMounted;
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (panelMounted)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value;
                if (t <= 0) return const SizedBox.shrink();
                return GestureDetector(
                  key: widget.scrimKey,
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onDismiss,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45 * t),
                  ),
                );
              },
            ),
          ),
        if (panelMounted)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: widget.width,
            child: _SlidePanel(
              controller: _controller,
              child: widget.panel,
            ),
          ),
      ],
    );
  }
}

class _SlidePanel extends StatelessWidget {
  const _SlidePanel({
    required this.controller,
    required this.child,
  });

  final AnimationController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final slide = Tween<Offset>(
      begin: const Offset(-1, 0),
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
