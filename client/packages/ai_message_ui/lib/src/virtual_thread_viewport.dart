import 'package:flutter/widgets.dart';

import 'thread_turns.dart';
import 'turn_height_cache.dart';

/// Spec default: 3 turns above and below the viewport.
const int kThreadOverscan = 3;

/// Spacer-based virtual list: mounts only the visible turn window (+ overscan).
///
/// Uses an explicit [ListView] child list (top/bottom spacers + mounted turns),
/// not [ListView.builder] per turn. Parent owns sticky-bottom while
/// [stickIntent] is true — measure-driven scroll corrections are skipped.
class VirtualThreadViewport extends StatefulWidget {
  const VirtualThreadViewport({
    required this.turns,
    required this.heightCache,
    required this.scrollController,
    required this.turnBuilder,
    this.overscan = kThreadOverscan,
    this.padding = const EdgeInsets.fromLTRB(0, 16, 0, 24),
    this.header,
    this.stickIntent = false,
    this.onHeightChanged,
    super.key,
  });

  final List<ThreadTurn> turns;
  final TurnHeightCache heightCache;
  final ScrollController scrollController;
  final Widget Function(BuildContext context, ThreadTurn turn) turnBuilder;
  final int overscan;
  final EdgeInsets padding;
  final Widget? header;
  final bool stickIntent;

  /// Fired after a turn height is recorded so the parent can re-stick while
  /// [stickIntent] is true (viewport skips measure-driven scroll jumps then).
  final VoidCallback? onHeightChanged;

  @override
  State<VirtualThreadViewport> createState() => _VirtualThreadViewportState();
}

class _VirtualThreadViewportState extends State<VirtualThreadViewport> {
  TurnVisibleRange _range = const TurnVisibleRange(
    firstIndex: 0,
    lastIndex: -1,
    paddingTop: 0,
    paddingBottom: 0,
  );
  double _headerHeight = 0;
  double _viewportHeight = 0;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScrollControllerTick);
    _range = _computeRange();
  }

  @override
  void didUpdateWidget(covariant VirtualThreadViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onScrollControllerTick);
      widget.scrollController.addListener(_onScrollControllerTick);
    }
    if (oldWidget.turns != widget.turns ||
        oldWidget.overscan != widget.overscan ||
        oldWidget.padding != widget.padding ||
        oldWidget.header != widget.header) {
      _recomputeRange();
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScrollControllerTick);
    super.dispose();
  }

  void _onScrollControllerTick() {
    _recomputeRange();
  }

  double get _contentOrigin =>
      widget.padding.top + (widget.header != null ? _headerHeight : 0);

  TurnVisibleRange _computeRange() {
    final turns = widget.turns;
    if (turns.isEmpty) {
      return const TurnVisibleRange(
        firstIndex: 0,
        lastIndex: -1,
        paddingTop: 0,
        paddingBottom: 0,
      );
    }
    final pixels = widget.scrollController.hasClients
        ? widget.scrollController.position.pixels
        : 0.0;
    final viewport = widget.scrollController.hasClients
        ? widget.scrollController.position.viewportDimension
        : _viewportHeight;
    final scrollIntoTurns = (pixels - _contentOrigin).clamp(
      0.0,
      double.infinity,
    );
    return widget.heightCache.visibleRange(
      turns: turns,
      scrollPixels: scrollIntoTurns,
      viewportHeight: viewport > 0 ? viewport : 1,
      overscan: widget.overscan,
    );
  }

  void _recomputeRange() {
    final next = _computeRange();
    if (next.firstIndex == _range.firstIndex &&
        next.lastIndex == _range.lastIndex &&
        next.paddingTop == _range.paddingTop &&
        next.paddingBottom == _range.paddingBottom) {
      return;
    }
    setState(() => _range = next);
  }

  void _onHeaderHeight(double height) {
    if ((height - _headerHeight).abs() < 0.5) return;
    setState(() {
      _headerHeight = height;
      _range = _computeRange();
    });
  }

  void _onTurnHeight(int index, String turnId, double height) {
    final previous = widget.heightCache.heightOf(turnId);
    if ((height - previous).abs() < 0.5) {
      // Still record so estimate→same-value does not keep missing cache entry.
      widget.heightCache.setMeasured(turnId, height);
      return;
    }

    // While parent is sticking, ignore shrinks so maxScrollExtent does not
    // collapse under the cursor and bounce/release stick intent.
    if (widget.stickIntent) {
      widget.heightCache.setMeasuredMonotonic(turnId, height);
      final next = widget.heightCache.heightOf(turnId);
      if ((next - previous).abs() < 0.5) return;
    } else {
      widget.heightCache.setMeasured(turnId, height);
    }

    final appliedDelta = widget.heightCache.heightOf(turnId) - previous;

    // Measure-driven scroll correction: keep content under the viewport stable
    // when a turn above the scroll offset changes height. Parent owns sticky.
    if (!widget.stickIntent &&
        widget.scrollController.hasClients &&
        appliedDelta != 0) {
      final turnTop = _contentOrigin + _offsetOfTurn(index);
      final pixels = widget.scrollController.position.pixels;
      if (turnTop < pixels) {
        final upper =
            widget.scrollController.position.maxScrollExtent + appliedDelta;
        if (upper >= 0) {
          final next = (pixels + appliedDelta).clamp(0.0, upper);
          widget.scrollController.jumpTo(next);
        }
      }
    } else if (widget.stickIntent) {
      // Spacers update this frame; parent re-sticks after layout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onHeightChanged?.call();
      });
    }

    setState(() => _range = _computeRange());
  }

  double _offsetOfTurn(int index) {
    var offset = 0.0;
    for (var i = 0; i < index; i++) {
      offset += widget.heightCache.heightOf(widget.turns[i].id);
    }
    return offset;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        if (maxH.isFinite && (maxH - _viewportHeight).abs() > 0.5) {
          _viewportHeight = maxH;
          final next = _computeRange();
          if (next.firstIndex != _range.firstIndex ||
              next.lastIndex != _range.lastIndex ||
              next.paddingTop != _range.paddingTop ||
              next.paddingBottom != _range.paddingBottom) {
            _range = next;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
          }
        }
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth == 0) {
              _recomputeRange();
            }
            return false;
          },
          // CustomScrollView + SliverToBoxAdapter so spacer heights contribute
          // exact scrollExtent. ListView/SliverList estimates unlaid-out
          // children from averages, which oscillates as the window moves.
          child: CustomScrollView(
            controller: widget.scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(height: widget.padding.top),
              ),
              if (widget.header != null)
                SliverToBoxAdapter(
                  child: _MeasuredBox(
                    onHeight: _onHeaderHeight,
                    child: widget.header!,
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(height: _range.paddingTop),
              ),
              if (_range.lastIndex >= _range.firstIndex)
                for (var i = _range.firstIndex; i <= _range.lastIndex; i++)
                  SliverToBoxAdapter(
                    child: _MeasuredTurn(
                      key: ValueKey(widget.turns[i].id),
                      turnId: widget.turns[i].id,
                      index: i,
                      layoutHeight:
                          widget.heightCache.heightOf(widget.turns[i].id),
                      onHeight: _onTurnHeight,
                      child: widget.turnBuilder(context, widget.turns[i]),
                    ),
                  ),
              SliverToBoxAdapter(
                child: SizedBox(height: _range.paddingBottom),
              ),
              SliverToBoxAdapter(
                child: SizedBox(height: widget.padding.bottom),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MeasuredTurn extends StatefulWidget {
  const _MeasuredTurn({
    required this.turnId,
    required this.index,
    required this.layoutHeight,
    required this.onHeight,
    required this.child,
    super.key,
  });

  final String turnId;
  final int index;
  final double layoutHeight;
  final void Function(int index, String turnId, double height) onHeight;
  final Widget child;

  @override
  State<_MeasuredTurn> createState() => _MeasuredTurnState();
}

class _MeasuredTurnState extends State<_MeasuredTurn> {
  final GlobalKey _measureKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  @override
  void didUpdateWidget(covariant _MeasuredTurn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.turnId != widget.turnId ||
        oldWidget.child != widget.child ||
        oldWidget.layoutHeight != widget.layoutHeight) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    }
  }

  void _report() {
    if (!mounted) return;
    final height = _measureKey.currentContext?.size?.height;
    if (height == null || height <= 0) return;
    widget.onHeight(widget.index, widget.turnId, height);
  }

  @override
  Widget build(BuildContext context) {
    // Drive list extent from the height cache (same as spacers). Measure the
    // child via a top-positioned stack slot with loose height.
    return SizedBox(
      height: widget.layoutHeight,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: NotificationListener<SizeChangedLayoutNotification>(
                onNotification: (_) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => _report());
                  return true;
                },
                child: SizeChangedLayoutNotifier(
                  key: _measureKey,
                  child: widget.child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeasuredBox extends StatefulWidget {
  const _MeasuredBox({required this.onHeight, required this.child});

  final ValueChanged<double> onHeight;
  final Widget child;

  @override
  State<_MeasuredBox> createState() => _MeasuredBoxState();
}

class _MeasuredBoxState extends State<_MeasuredBox> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  void _report() {
    if (!mounted) return;
    final height = context.size?.height;
    if (height == null || height <= 0) return;
    widget.onHeight(height);
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _report());
        return true;
      },
      child: SizeChangedLayoutNotifier(child: widget.child),
    );
  }
}
