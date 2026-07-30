import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

const kAiFadeExpandCollapsedMaxHeight = 120.0;
const kAiFadeExpandExpandedMaxHeight = 320.0;
const kAiFadeExpandHitStripHeight = 32.0;

class AiFadeExpandBody extends StatefulWidget {
  const AiFadeExpandBody({
    required this.open,
    required this.onToggle,
    required this.fadeColor,
    required this.child,
    this.collapsedMaxHeight = kAiFadeExpandCollapsedMaxHeight,
    this.expandedMaxHeight = kAiFadeExpandExpandedMaxHeight,
    super.key,
  });

  final bool open;
  final VoidCallback onToggle;
  final Color fadeColor;
  final Widget child;
  final double collapsedMaxHeight;
  final double expandedMaxHeight;

  @override
  State<AiFadeExpandBody> createState() => _AiFadeExpandBodyState();
}

class _AiFadeExpandBodyState extends State<AiFadeExpandBody> {
  double? _childHeight;

  void _onMeasured(Size size) {
    if (!mounted) return;
    if (_childHeight == size.height) return;
    setState(() => _childHeight = size.height);
  }

  /// Measure-only probe: zero Stack contribution and **never paints**.
  /// Painting a full OverflowBox copy here previously bled through bubble
  /// chrome (DecoratedBox does not clip) into messages below.
  Widget _probe(double maxWidth, Widget child) => Positioned(
        left: 0,
        top: 0,
        width: maxWidth,
        height: 0,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: maxWidth,
              maxWidth: maxWidth,
              minHeight: 0,
              maxHeight: double.infinity,
              child: _ReportSize(onSize: _onMeasured, child: child),
            ),
          ),
        ),
      );

  /// Clip tall content to [height] via scroll viewport (clips paint reliably).
  Widget _viewportClip({required double height, required Widget child}) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRect(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final measured = _childHeight;
    final overflows = measured != null && measured > widget.collapsedMaxHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        if (measured == null) {
          // Clip-until-measured: maxHeight only — short content keeps natural height.
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              _probe(maxW, child),
              ConstrainedBox(
                constraints:
                    BoxConstraints(maxHeight: widget.collapsedMaxHeight),
                child: ClipRect(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: child,
                  ),
                ),
              ),
            ],
          );
        }

        if (!overflows) {
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              _probe(maxW, child),
              child,
            ],
          );
        }

        if (!widget.open) {
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              _probe(maxW, child),
              SizedBox(
                height: widget.collapsedMaxHeight,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    _viewportClip(
                      height: widget.collapsedMaxHeight,
                      child: child,
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: _FadeChevronHit(
                        fadeColor: widget.fadeColor,
                        icon: Icons.expand_more,
                        onTap: widget.onToggle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final needsScroll = measured > widget.expandedMaxHeight;
        Widget body = child;
        if (needsScroll) {
          body = ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.expandedMaxHeight),
            child: SingleChildScrollView(child: child),
          );
        }

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            _probe(maxW, child),
            body,
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _FadeChevronHit(
                fadeColor: widget.fadeColor,
                icon: Icons.expand_less,
                onTap: widget.onToggle,
                showFade: needsScroll,
              ),
            ),
          ],
        );
      },
    );
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

class _ReportSize extends SingleChildRenderObjectWidget {
  const _ReportSize({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReportSize(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderReportSize renderObject) {
    renderObject.onSize = onSize;
  }
}

class _RenderReportSize extends RenderProxyBox {
  _RenderReportSize(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

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
    // Probe must not inflate Stack; report child height via callback only.
    size = constraints.smallest;
    final measured = child.size;
    if (_last != measured) {
      _last = measured;
      WidgetsBinding.instance.addPostFrameCallback((_) => onSize(measured));
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // Measure-only: never paint the probe copy (prevents bleed-through).
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;
}
