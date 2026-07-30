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

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final measured = _childHeight;
    final overflows = measured != null && measured > widget.collapsedMaxHeight;

    // Clip-until-measured: avoid one-frame full flash.
    // Probe must NOT inflate Stack size (see File map measurement strategy A).
    Widget probe(double maxWidth) => Positioned(
          left: 0,
          top: 0,
          width: maxWidth,
          height: 0,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: maxWidth,
            maxWidth: maxWidth,
            minHeight: 0,
            maxHeight: double.infinity,
            child: _ReportSize(onSize: _onMeasured, child: child),
          ),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        if (measured == null) {
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              probe(maxW),
              SizedBox(
                height: widget.collapsedMaxHeight,
                width: double.infinity,
                child: ClipRect(
                  child: _collapsedClipChild(maxW, child),
                ),
              ),
            ],
          );
        }

        if (!overflows) {
          return Stack(
            children: [
              probe(maxW),
              child,
            ],
          );
        }

        if (!widget.open) {
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              probe(maxW),
              SizedBox(
                height: widget.collapsedMaxHeight,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRect(
                      child: _collapsedClipChild(maxW, child),
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
            probe(maxW),
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

Widget _collapsedClipChild(double maxWidth, Widget child) {
  return OverflowBox(
    alignment: Alignment.topLeft,
    minWidth: maxWidth,
    maxWidth: maxWidth,
    minHeight: 0,
    maxHeight: double.infinity,
    child: child,
  );
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
}
