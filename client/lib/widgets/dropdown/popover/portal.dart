// Overlay portal adapted from AppFlowy UI / flutter_shadcn_ui.

import 'package:flutter/material.dart';

import 'anchor.dart';

class AppPortal extends StatefulWidget {
  const AppPortal({
    super.key,
    required this.child,
    required this.portalBuilder,
    required this.visible,
    required this.anchor,
    this.transitionDuration = const Duration(milliseconds: 160),
    this.transitionCurve = Curves.easeOutCubic,
  });

  final Widget child;
  final WidgetBuilder portalBuilder;
  final bool visible;
  final AppAnchorBase anchor;
  final Duration transitionDuration;
  final Curve transitionCurve;

  @override
  State<AppPortal> createState() => _AppPortalState();
}

class _AppPortalState extends State<AppPortal> with SingleTickerProviderStateMixin {
  final layerLink = LayerLink();
  final overlayPortalController = OverlayPortalController();
  final overlayKey = GlobalKey();
  final _targetKey = GlobalKey();
  late final AnimationController _transitionController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _transitionController = AnimationController(
      vsync: this,
      duration: widget.transitionDuration,
    );
    final curved = CurvedAnimation(
      parent: _transitionController,
      curve: widget.transitionCurve,
      reverseCurve: Curves.easeInCubic,
    );
    _fadeAnimation = curved;
    _scaleAnimation = Tween<double>(begin: 0.97, end: 1).animate(curved);
    _updateVisibility();
  }

  @override
  void didUpdateWidget(covariant AppPortal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transitionDuration != widget.transitionDuration) {
      _transitionController.duration = widget.transitionDuration;
    }
    _updateVisibility();
  }

  @override
  void dispose() {
    _transitionController.dispose();
    _hide();
    super.dispose();
  }

  void _updateVisibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.visible) {
        _show();
        if (widget.transitionDuration == Duration.zero) {
          _transitionController.value = 1.0;
          return;
        }
        // Always forward — handles re-open after reverse, and re-open while
        // reverse is still running (otherwise opacity stays at 0).
        _transitionController.forward();
        return;
      }
      if (widget.transitionDuration == Duration.zero) {
        _transitionController.value = 0.0;
        _hide();
        return;
      }
      if (_transitionController.value <= 0) {
        _hide();
        return;
      }
      _transitionController.reverse().whenComplete(() {
        if (!mounted) return;
        if (widget.visible) {
          _show();
          _transitionController.forward(from: 0);
          return;
        }
        _hide();
      });
    });
  }

  void _hide() {
    if (overlayPortalController.isShowing) {
      overlayPortalController.hide();
    }
  }

  void _show() {
    if (!overlayPortalController.isShowing) {
      overlayPortalController.show();
    }
  }

  Alignment _transitionAlignment(AppAnchorBase anchor) {
    return switch (anchor) {
      AppAnchor anchor => anchor.childAlignment,
      AppAnchorAuto anchor => anchor.followerAnchor,
      AppGlobalAnchor _ => Alignment.topCenter,
    };
  }

  Widget _buildAnimatedPortal(BuildContext context, Widget child) {
    if (widget.transitionDuration == Duration.zero) {
      return child;
    }
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        alignment: _transitionAlignment(widget.anchor),
        child: child,
      ),
    );
  }

  Widget _buildAutoPosition(BuildContext context, AppAnchorAuto anchor) {
    if (anchor.followTargetOnResize) {
      MediaQuery.sizeOf(context);
    }
    final overlayState = Overlay.of(context, debugRequiredFor: widget);
    // overlayChildBuilder's [context] is not the anchor — use [_targetKey].
    final box = _targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return const SizedBox.shrink();
    }
    final overlayAncestor =
        overlayState.context.findRenderObject()! as RenderBox;

    final overlay = overlayKey.currentContext?.findRenderObject() as RenderBox?;
    final overlaySize =
        overlay != null && overlay.hasSize ? overlay.size : Size.zero;
    final needsMeasure = overlay == null || !overlay.hasSize;

    final targetOffset = switch (anchor.targetAnchor) {
      Alignment.topLeft => box.size.topLeft(Offset.zero),
      Alignment.topCenter => box.size.topCenter(Offset.zero),
      Alignment.topRight => box.size.topRight(Offset.zero),
      Alignment.centerLeft => box.size.centerLeft(Offset.zero),
      Alignment.center => box.size.center(Offset.zero),
      Alignment.centerRight => box.size.centerRight(Offset.zero),
      Alignment.bottomLeft => box.size.bottomLeft(Offset.zero),
      Alignment.bottomCenter => box.size.bottomCenter(Offset.zero),
      Alignment.bottomRight => box.size.bottomRight(Offset.zero),
      final alignment => throw Exception(
          'AppAnchorAuto does not support alignment $alignment',
        ),
    };

    var followerOffset = switch (anchor.followerAnchor) {
      Alignment.topLeft => Offset(-overlaySize.width / 2, -overlaySize.height),
      Alignment.topCenter => Offset(0, -overlaySize.height),
      Alignment.topRight => Offset(overlaySize.width / 2, -overlaySize.height),
      Alignment.centerLeft =>
        Offset(-overlaySize.width / 2, -overlaySize.height / 2),
      Alignment.center => Offset(0, -overlaySize.height / 2),
      Alignment.centerRight =>
        Offset(overlaySize.width / 2, -overlaySize.height / 2),
      Alignment.bottomLeft => Offset(-overlaySize.width / 2, 0),
      Alignment.bottomCenter => Offset.zero,
      Alignment.bottomRight => Offset(overlaySize.width / 2, 0),
      final alignment => throw Exception(
          'AppAnchorAuto does not support alignment $alignment',
        ),
    };

    followerOffset += targetOffset + anchor.offset;

    final target = box.localToGlobal(
      followerOffset,
      ancestor: overlayAncestor,
    );

    if (needsMeasure) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    return CustomSingleChildLayout(
      delegate: _AppPositionDelegate(
        target: target,
        verticalOffset: 0,
        preferBelow: true,
      ),
      child: KeyedSubtree(
        key: overlayKey,
        child: _buildAnimatedPortal(
          context,
          widget.portalBuilder(context),
        ),
      ),
    );
  }

  Widget _buildManualPosition(BuildContext context, AppAnchor anchor) {
    return CompositedTransformFollower(
      link: layerLink,
      offset: anchor.offset,
      followerAnchor: anchor.childAlignment,
      targetAnchor: anchor.overlayAlignment,
      child: _buildAnimatedPortal(context, widget.portalBuilder(context)),
    );
  }

  Widget _buildGlobalPosition(BuildContext context, AppGlobalAnchor anchor) {
    return CustomSingleChildLayout(
      delegate: _AppPositionDelegate(
        target: anchor.offset,
        verticalOffset: 0,
        preferBelow: true,
      ),
      child: _buildAnimatedPortal(context, widget.portalBuilder(context)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      key: _targetKey,
      link: layerLink,
      child: OverlayPortal(
        controller: overlayPortalController,
        overlayChildBuilder: (context) {
          return Material(
            type: MaterialType.transparency,
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: switch (widget.anchor) {
                final AppAnchorAuto anchor => _buildAutoPosition(context, anchor),
                final AppAnchor anchor => _buildManualPosition(context, anchor),
                final AppGlobalAnchor anchor =>
                  _buildGlobalPosition(context, anchor),
              },
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _AppPositionDelegate extends SingleChildLayoutDelegate {
  _AppPositionDelegate({
    required this.target,
    required this.verticalOffset,
    required this.preferBelow,
  });

  final Offset target;
  final double verticalOffset;
  final bool preferBelow;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return positionDependentBox(
      size: size,
      childSize: childSize,
      target: target,
      verticalOffset: verticalOffset,
      preferBelow: preferBelow,
      margin: 0,
    );
  }

  @override
  bool shouldRelayout(_AppPositionDelegate oldDelegate) {
    return target != oldDelegate.target ||
        verticalOffset != oldDelegate.verticalOffset ||
        preferBelow != oldDelegate.preferBelow;
  }
}
