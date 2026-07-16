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

    final delta = height - previous;
    widget.heightCache.setMeasured(turnId, height);

    // Measure-driven scroll correction: keep content under the viewport stable
    // when a turn above the scroll offset changes height. Parent owns sticky.
    if (!widget.stickIntent &&
        widget.scrollController.hasClients &&
        delta != 0) {
      final turnTop = _contentOrigin + _offsetOfTurn(index);
      final pixels = widget.scrollController.position.pixels;
      if (turnTop < pixels) {
        final next = (pixels + delta).clamp(
          0.0,
          widget.scrollController.position.maxScrollExtent + delta,
        );
        widget.scrollController.jumpTo(next);
      }
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
          child: ListView(
            controller: widget.scrollController,
            padding: widget.padding,
            children: [
              if (widget.header != null)
                _MeasuredBox(
                  onHeight: _onHeaderHeight,
                  child: widget.header!,
                ),
              SizedBox(height: _range.paddingTop),
              if (_range.lastIndex >= _range.firstIndex)
                for (var i = _range.firstIndex; i <= _range.lastIndex; i++)
                  _MeasuredTurn(
                    key: ValueKey(widget.turns[i].id),
                    turnId: widget.turns[i].id,
                    index: i,
                    onHeight: _onTurnHeight,
                    child: widget.turnBuilder(context, widget.turns[i]),
                  ),
              SizedBox(height: _range.paddingBottom),
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
    required this.onHeight,
    required this.child,
    super.key,
  });

  final String turnId;
  final int index;
  final void Function(int index, String turnId, double height) onHeight;
  final Widget child;

  @override
  State<_MeasuredTurn> createState() => _MeasuredTurnState();
}

class _MeasuredTurnState extends State<_MeasuredTurn> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  @override
  void didUpdateWidget(covariant _MeasuredTurn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.turnId != widget.turnId || oldWidget.child != widget.child) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    }
  }

  void _report() {
    if (!mounted) return;
    final height = context.size?.height;
    if (height == null || height <= 0) return;
    widget.onHeight(widget.index, widget.turnId, height);
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
