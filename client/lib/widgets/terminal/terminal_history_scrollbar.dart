import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_alacritty/input/term_mode.dart' show kModeAltScreen;

import 'terminal_scrollbar_geometry.dart';

/// History scrollbar mapped like VTE + GtkAdjustment.
///
/// Ported from flutter_alacritty's example (not library API).
///
/// Thumb geometry paints via [CustomPainter.repaint] on [TerminalEngine.repaint]
/// so PTY cell / history ticks do not rebuild [GestureDetector]. Widget rebuilds
/// are reserved for track visibility (history empty / alt-screen) and drag.
class TerminalHistoryScrollbar extends StatefulWidget {
  const TerminalHistoryScrollbar({
    required this.engine,
    required this.controller,
    super.key,
  });

  final TerminalEngine engine;
  final TerminalController controller;

  @override
  State<TerminalHistoryScrollbar> createState() =>
      _TerminalHistoryScrollbarState();
}

class _TerminalHistoryScrollbarState extends State<TerminalHistoryScrollbar> {
  bool _dragging = false;
  double? _dragPositionFraction;
  late bool _trackVisible;

  /// Coalesce rapid drag events: only the latest target is applied.
  double? _pendingPositionFraction;
  bool _scrollInFlight = false;
  int _scrollGeneration = 0;

  @override
  void initState() {
    super.initState();
    _trackVisible = _isTrackVisible();
    widget.engine.repaint.addListener(_onGridChanged);
  }

  @override
  void didUpdateWidget(covariant TerminalHistoryScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.engine != widget.engine) {
      oldWidget.engine.repaint.removeListener(_onGridChanged);
      widget.engine.repaint.addListener(_onGridChanged);
      _trackVisible = _isTrackVisible();
    }
  }

  @override
  void dispose() {
    widget.engine.repaint.removeListener(_onGridChanged);
    super.dispose();
  }

  bool _isTrackVisible() {
    final grid = widget.engine.grid;
    return grid.historySize > 0 && (grid.modeFlags & kModeAltScreen) == 0;
  }

  void _onGridChanged() {
    if (!mounted) return;
    final visible = _isTrackVisible();
    if (visible != _trackVisible) {
      setState(() => _trackVisible = visible);
    }
  }

  TerminalScrollbarGeometry _geometry(double trackHeight) {
    final grid = widget.engine.grid;
    return TerminalScrollbarGeometry(
      historySize: grid.historySize,
      viewportRows: grid.rows,
      scrollOffsetLines: grid.displayOffset + grid.scrollFraction,
      trackHeight: trackHeight,
    );
  }

  Future<void> _scrollToPositionFraction(double positionFraction) async {
    final grid = widget.engine.grid;
    final historySize = grid.historySize;
    if (historySize <= 0) return;

    final geom = TerminalScrollbarGeometry(
      historySize: historySize,
      viewportRows: grid.rows,
      scrollOffsetLines: 0,
      trackHeight: 1,
    );

    if (geom.isNearLiveBottom(positionFraction)) {
      await widget.controller.scrollToBottom();
      return;
    }
    if (geom.isNearHistoryTop(positionFraction)) {
      await widget.controller.scrollToTop();
      return;
    }

    final target = geom.scrollOffsetForPosition(positionFraction);
    await widget.controller.scrollToOffset(target);
  }

  Future<void> _drainPendingScroll() async {
    if (_scrollInFlight) return;
    _scrollInFlight = true;
    try {
      while (_pendingPositionFraction != null) {
        final fraction = _pendingPositionFraction!;
        _pendingPositionFraction = null;
        final gen = ++_scrollGeneration;
        await _scrollToPositionFraction(fraction);
        if (gen != _scrollGeneration) return;
      }
    } finally {
      _scrollInFlight = false;
      if (_pendingPositionFraction != null) {
        await _drainPendingScroll();
      }
    }
  }

  void _onTrackPointer(double localDy, double trackHeight) {
    if (trackHeight <= 0) return;
    final geom = _geometry(trackHeight);
    if (!geom.visible) return;

    final positionFraction =
        TerminalScrollbarGeometry.positionFractionFromTrackDy(
          localDy: localDy,
          trackHeight: trackHeight,
          thumbHeight: geom.thumbHeight,
        );
    _pendingPositionFraction = positionFraction;
    if (_dragging) {
      _dragPositionFraction = positionFraction;
      setState(() {});
    }
    _drainPendingScroll();
  }

  @override
  Widget build(BuildContext context) {
    if (!_trackVisible) {
      return const SizedBox(width: 0);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackHeight = constraints.maxHeight;
        if (trackHeight <= 0) return const SizedBox(width: 0);

        final theme = ScrollbarTheme.of(context);
        final thickness = theme.thickness?.resolve({}) ?? 8.0;
        final radius = theme.radius ?? const Radius.circular(8);
        // Match Material [Scrollbar] defaults (same as file tree / panels).
        final onSurface = Theme.of(context).colorScheme.onSurface;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final trackColor = theme.trackColor?.resolve({}) ?? Colors.transparent;
        final idleThumb = onSurface.withValues(alpha: isDark ? 0.3 : 0.1);
        final dragThumb = onSurface.withValues(alpha: isDark ? 0.75 : 0.6);
        final thumbColor =
            theme.thumbColor?.resolve({}) ??
            (_dragging ? dragThumb : idleThumb);

        return SizedBox(
          width: 12,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) {
              _scrollGeneration++;
              widget.engine.cancelCoalescedScrollInput();
              _dragging = true;
              _dragPositionFraction = null;
            },
            onVerticalDragEnd: (_) {
              _dragging = false;
              _dragPositionFraction = null;
              setState(() {});
            },
            onVerticalDragCancel: () {
              _dragging = false;
              _dragPositionFraction = null;
              setState(() {});
            },
            onVerticalDragUpdate: (d) =>
                _onTrackPointer(d.localPosition.dy, trackHeight),
            onTapDown: (d) {
              _scrollGeneration++;
              widget.engine.cancelCoalescedScrollInput();
              _onTrackPointer(d.localPosition.dy, trackHeight);
            },
            child: CustomPaint(
              painter: _ScrollbarPainter(
                grid: widget.engine.grid,
                dragPositionFraction: _dragPositionFraction,
                trackWidth: thickness,
                radius: radius,
                trackColor: trackColor,
                thumbColor: thumbColor,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

class _ScrollbarPainter extends CustomPainter {
  _ScrollbarPainter({
    required this.grid,
    required this.dragPositionFraction,
    required this.trackWidth,
    required this.radius,
    required this.trackColor,
    required this.thumbColor,
  }) : super(repaint: grid);

  final TerminalGridView grid;
  final double? dragPositionFraction;
  final double trackWidth;
  final Radius radius;
  final Color trackColor;
  final Color thumbColor;

  @override
  void paint(Canvas canvas, Size size) {
    final geom = TerminalScrollbarGeometry(
      historySize: grid.historySize,
      viewportRows: grid.rows,
      scrollOffsetLines: grid.displayOffset + grid.scrollFraction,
      trackHeight: size.height,
    );
    if (!geom.visible) return;

    final paintFraction = dragPositionFraction ?? geom.positionFraction;
    final thumbTop = geom.thumbTopAt(paintFraction);

    final trackR = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width - trackWidth - 2, 0, trackWidth, size.height),
      radius,
    );
    canvas.drawRRect(trackR, Paint()..color = trackColor);

    final thumbR = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width - trackWidth - 2,
        thumbTop,
        trackWidth,
        geom.thumbHeight.clamp(0, size.height),
      ),
      radius,
    );
    canvas.drawRRect(thumbR, Paint()..color = thumbColor);
  }

  @override
  bool shouldRepaint(covariant _ScrollbarPainter old) =>
      old.grid != grid ||
      old.dragPositionFraction != dragPositionFraction ||
      old.trackWidth != trackWidth ||
      old.thumbColor != thumbColor ||
      old.trackColor != trackColor ||
      old.radius != radius;
}
