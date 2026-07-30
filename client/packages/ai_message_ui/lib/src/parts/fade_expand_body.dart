import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

const kAiFadeExpandCollapsedMaxHeight = 120.0;
const kAiFadeExpandExpandedMaxHeight = 320.0;
const kAiFadeExpandHitStripHeight = 32.0;

/// Collapsed fade + chevron / expanded scroll shell.
///
/// Mounts [child] **once**. A custom render object lays the child out at full
/// height, reports that height, and clips paint when collapsed — avoiding the
/// dual probe+visible tree that doubled layout cost on long edit diffs / bubbles.
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
    super.key,
  });

  final bool open;
  final VoidCallback onToggle;
  final Color fadeColor;
  final Widget child;
  final double collapsedMaxHeight;
  final double expandedMaxHeight;
  final bool forceChrome;

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
        oldWidget.expandedMaxHeight != widget.expandedMaxHeight) {
      // Mode change may need scroll↔clip swap; height stays valid.
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final overflows = _overflows;
    final needsScroll = _needsScroll;

    // Until measured, clip at collapsed max (short content sizes naturally
    // inside the render object once height is known on the same layout pass).
    final clipAt = needsScroll
        ? null
        : (!widget.open || _childHeight == null)
            ? widget.collapsedMaxHeight
            : null;

    final Widget body;
    if (needsScroll) {
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
        clipMaxHeight: clipAt,
        // When expanded mid-length, never clip; when collapsed / unknown, clip.
        forceClip: _childHeight == null || (!widget.open && overflows),
        onHeight: _onChildHeight,
        child: child,
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
            child: _FadeChevronHit(
              fadeColor: widget.fadeColor,
              icon: widget.open ? Icons.expand_less : Icons.expand_more,
              onTap: widget.onToggle,
              showFade: !widget.open || needsScroll,
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

class _FadeChevronHit extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: kAiFadeExpandHitStripHeight,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (showFade)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      fadeColor.withValues(alpha: 0),
                      fadeColor,
                    ],
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            Icon(
              icon,
              key: const ValueKey('ai-fade-expand-chevron'),
              size: 18,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.55),
            ),
          ],
        ),
      ),
    );
  }
}
