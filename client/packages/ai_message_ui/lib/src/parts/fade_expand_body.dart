import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../selection_dead_zone.dart';

const kAiFadeExpandCollapsedMaxHeight = 120.0;
const kAiFadeExpandExpandedMaxHeight = 320.0;
const kAiFadeExpandHitStripHeight = 32.0;

/// Collapsed fade + chevron / expanded scroll shell.
///
/// Lays [child] out once per build. Collapsed: full-height layout + paint clip.
/// Open: always capped at [expandedMaxHeight] inside a scroll view so swapping
/// a short preview for a tall body (edit cards) never flashes unbounded height.
class AiFadeExpandBody extends StatefulWidget {
  const AiFadeExpandBody({
    required this.open,
    required this.onToggle,
    required this.fadeColor,
    required this.child,
    this.collapsedMaxHeight = kAiFadeExpandCollapsedMaxHeight,
    this.expandedMaxHeight = kAiFadeExpandExpandedMaxHeight,
    /// When true, show fade/chevron even if [child] fits in collapsed max
    /// (e.g. edit card mounts a short preview but more lines exist off-tree).
    this.forceChrome = false,
    this.contentPadding = EdgeInsets.zero,
    super.key,
  });

  final bool open;
  final VoidCallback onToggle;
  final Color fadeColor;
  final Widget child;
  final double collapsedMaxHeight;
  final double expandedMaxHeight;
  final bool forceChrome;
  final EdgeInsetsGeometry contentPadding;

  @override
  State<AiFadeExpandBody> createState() => _AiFadeExpandBodyState();
}

class _AiFadeExpandBodyState extends State<AiFadeExpandBody> {
  double? _childHeight;

  bool get _overflows =>
      widget.forceChrome ||
      (_childHeight != null && _childHeight! > widget.collapsedMaxHeight);

  bool get _needsScroll =>
      widget.open &&
      _childHeight != null &&
      _childHeight! > widget.expandedMaxHeight;

  void _onChildHeight(double height) {
    if (!mounted) return;
    final prev = _childHeight;
    if (prev == height) return;

    final wasOverflow =
        prev != null && prev > widget.collapsedMaxHeight;
    final nowOverflow = height > widget.collapsedMaxHeight;
    final wasScroll =
        widget.open && prev != null && prev > widget.expandedMaxHeight;
    final nowScroll =
        widget.open && height > widget.expandedMaxHeight;

    _childHeight = height;
    // Rebuild only when chrome / scroll mode changes — keep child stable.
    if (prev == null ||
        wasOverflow != nowOverflow ||
        wasScroll != nowScroll) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant AiFadeExpandBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open != widget.open ||
        oldWidget.forceChrome != widget.forceChrome ||
        oldWidget.collapsedMaxHeight != widget.collapsedMaxHeight ||
        oldWidget.expandedMaxHeight != widget.expandedMaxHeight ||
        oldWidget.contentPadding != widget.contentPadding) {
      // Mode change may need scroll↔clip swap; height stays valid.
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final overflows = _overflows;
    final needsScroll = _needsScroll;

    Widget body;
    if (widget.open) {
      // Always cap at expanded max while open. Edit cards swap short preview →
      // full hunk on expand; a stale small `_childHeight` must not briefly
      // layout the full child unbounded before the scroll path kicks in.
      body = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.expandedMaxHeight),
        child: SingleChildScrollView(
          child: _HeightReporter(
            onHeight: _onChildHeight,
            child: child,
          ),
        ),
      );
    } else {
      body = _FadeExpandClip(
        clipMaxHeight: widget.collapsedMaxHeight,
        forceClip: _childHeight == null || overflows,
        onHeight: _onChildHeight,
        child: child,
      );
    }

    body = Padding(padding: widget.contentPadding, child: body);

    // Keep body text under the fade strip out of hit-testing / selection.
    if (overflows) {
      body = _BlockBottomHits(
        blockedHeight: kAiFadeExpandHitStripHeight,
        child: body,
      );
    }

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        body,
        if (overflows)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SelectionDeadZone(
              child: _FadeChevronHit(
                fadeColor: widget.fadeColor,
                icon: widget.open ? Icons.expand_less : Icons.expand_more,
                onTap: widget.onToggle,
                showFade: !widget.open || needsScroll,
              ),
            ),
          ),
      ],
    );
  }
}

/// Layouts [child] at full height (max width only), reports height, optionally
/// sizes itself to [clipMaxHeight] and clips paint.
class _FadeExpandClip extends SingleChildRenderObjectWidget {
  const _FadeExpandClip({
    required this.onHeight,
    required this.forceClip,
    this.clipMaxHeight,
    required super.child,
  });

  final ValueChanged<double> onHeight;
  final double? clipMaxHeight;
  final bool forceClip;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderFadeExpandClip(
      onHeight: onHeight,
      clipMaxHeight: clipMaxHeight,
      forceClip: forceClip,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFadeExpandClip renderObject,
  ) {
    renderObject
      ..onHeight = onHeight
      ..clipMaxHeight = clipMaxHeight
      ..forceClip = forceClip;
  }
}

class _RenderFadeExpandClip extends RenderProxyBox {
  _RenderFadeExpandClip({
    required this.onHeight,
    required this.clipMaxHeight,
    required this.forceClip,
  });

  ValueChanged<double> onHeight;
  double? clipMaxHeight;
  bool forceClip;
  double? _lastReported;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }

    child.layout(
      BoxConstraints(maxWidth: constraints.maxWidth),
      parentUsesSize: true,
    );
    final childSize = child.size;
    final height = childSize.height;

    if (_lastReported != height) {
      _lastReported = height;
      final reported = height;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onHeight(reported);
      });
    }

    final maxClip = clipMaxHeight;
    final shouldClip =
        forceClip && maxClip != null && height > maxClip;
    if (shouldClip) {
      size = constraints.constrain(Size(childSize.width, maxClip));
    } else {
      size = constraints.constrain(childSize);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;

    final maxClip = clipMaxHeight;
    final shouldClip =
        forceClip && maxClip != null && child.size.height > size.height;
    if (shouldClip) {
      context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        (context, offset) => context.paintChild(child, offset),
      );
    } else {
      context.paintChild(child, offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (child == null) return false;
    if (position.dy < 0 || position.dy > size.height) return false;
    if (position.dx < 0 || position.dx > size.width) return false;
    return super.hitTestChildren(result, position: position);
  }
}

/// Reports intrinsic height while participating normally in layout (scroll path).
class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({
    required this.onHeight,
    required super.child,
  });

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightReporter renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderHeightReporter extends RenderProxyBox {
  _RenderHeightReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _lastReported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (_lastReported == height) return;
    _lastReported = height;
    final reported = height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onHeight(reported);
    });
  }
}

/// Skips hit tests in the bottom [blockedHeight] so an overlay (fade strip)
/// owns that band exclusively — body text there cannot be selected.
class _BlockBottomHits extends SingleChildRenderObjectWidget {
  const _BlockBottomHits({
    required this.blockedHeight,
    required super.child,
  });

  final double blockedHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBlockBottomHits(blockedHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderBlockBottomHits renderObject,
  ) {
    renderObject.blockedHeight = blockedHeight;
  }
}

class _RenderBlockBottomHits extends RenderProxyBox {
  _RenderBlockBottomHits(this.blockedHeight);

  double blockedHeight;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (position.dy > size.height - blockedHeight) return false;
    return super.hitTest(result, position: position);
  }
}

class _FadeChevronHit extends StatefulWidget {
  const _FadeChevronHit({
    required this.fadeColor,
    required this.icon,
    required this.onTap,
    this.showFade = true,
  });

  final Color fadeColor;
  final IconData icon;
  final VoidCallback onTap;
  final bool showFade;

  @override
  State<_FadeChevronHit> createState() => _FadeChevronHitState();
}

class _FadeChevronHitState extends State<_FadeChevronHit> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final fadeEnd = _hovering
        ? Color.alphaBlend(onSurface.withValues(alpha: 0.14), widget.fadeColor)
        : widget.fadeColor;
    final iconAlpha = _hovering ? 0.78 : 0.55;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          _MaskPointerRecognizer:
              GestureRecognizerFactoryWithHandlers<_MaskPointerRecognizer>(
            () => _MaskPointerRecognizer(onTap: widget.onTap),
            (instance) => instance.onTap = widget.onTap,
          ),
        },
        child: SizedBox(
          height: kAiFadeExpandHitStripHeight,
          width: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.showFade)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        fadeEnd.withValues(alpha: 0),
                        fadeEnd,
                      ],
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              Icon(
                widget.icon,
                key: const ValueKey('ai-fade-expand-chevron'),
                size: 18,
                color: onSurface.withValues(alpha: iconAlpha),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wins the gesture arena on pointer-down so ancestor [SelectableRegion]
/// cannot start a text selection through the fade overlay.
class _MaskPointerRecognizer extends OneSequenceGestureRecognizer {
  _MaskPointerRecognizer({this.onTap});

  VoidCallback? onTap;
  int? _pointer;
  Offset? _startGlobal;

  @override
  void addPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    _pointer = event.pointer;
    _startGlobal = event.position;
    resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerUpEvent) {
      final start = _startGlobal;
      if (start != null &&
          (event.position - start).distance <= kTouchSlop) {
        onTap?.call();
      }
      _clear(event.pointer);
    } else if (event is PointerCancelEvent) {
      _clear(event.pointer);
    }
  }

  void _clear(int pointer) {
    stopTrackingPointer(pointer);
    _pointer = null;
    _startGlobal = null;
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    stopTrackingPointer(pointer);
    if (_pointer == pointer) {
      _pointer = null;
      _startGlobal = null;
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'maskPointer';
}
