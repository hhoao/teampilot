import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../services/diff/diff_model.dart';

/// IDE-style overview ruler: a thin strip on the far right showing every change
/// across the whole file (not just the visible area), plus a viewport indicator.
/// Tap or drag to jump to a position.
class DiffOverviewRuler extends StatelessWidget {
  const DiffOverviewRuler({
    required this.blocks,
    required this.totalRows,
    required this.scroll,
    required this.lineHeight,
    required this.topPadding,
    this.trackColor,
    super.key,
  });

  static const double width = 14;

  final List<DiffBlock> blocks;
  final int totalRows;
  final CodeScrollController scroll;
  final double lineHeight;
  final double topPadding;
  final Color? trackColor;

  double _contentHeight() {
    final pos = scroll.verticalScroller.hasClients
        ? scroll.verticalScroller.position
        : null;
    if (pos != null && pos.hasContentDimensions) {
      return pos.maxScrollExtent + pos.viewportDimension;
    }
    return totalRows * lineHeight + 2 * topPadding;
  }

  void _jumpToFraction(double fraction) {
    final scroller = scroll.verticalScroller;
    if (!scroller.hasClients) return;
    final pos = scroller.position;
    final contentHeight = pos.maxScrollExtent + pos.viewportDimension;
    final target = (fraction * contentHeight - pos.viewportDimension / 2)
        .clamp(0.0, pos.maxScrollExtent);
    scroller.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _jumpToFraction(d.localPosition.dy / height),
            onVerticalDragUpdate: (d) =>
                _jumpToFraction(d.localPosition.dy / height),
            child: ListenableBuilder(
              listenable: scroll.verticalScroller,
              builder: (context, _) {
                final scroller = scroll.verticalScroller;
                final hasClients = scroller.hasClients &&
                    scroller.position.hasContentDimensions;
                final contentHeight = _contentHeight();
                return CustomPaint(
                  painter: _OverviewRulerPainter(
                    blocks: blocks,
                    totalRows: totalRows,
                    lineHeight: lineHeight,
                    topPadding: topPadding,
                    contentHeight: contentHeight,
                    scrollOffset: hasClients ? scroller.offset : 0,
                    viewportExtent:
                        hasClients ? scroller.position.viewportDimension : 0,
                    trackColor: trackColor ?? cs.surfaceContainerHighest,
                    viewportColor: cs.onSurface.withValues(alpha: 0.12),
                    addColor: const Color(0xFF2EA043),
                    removeColor: cs.error,
                    modifyColor: cs.primary,
                  ),
                  child: const SizedBox.expand(),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _OverviewRulerPainter extends CustomPainter {
  _OverviewRulerPainter({
    required this.blocks,
    required this.totalRows,
    required this.lineHeight,
    required this.topPadding,
    required this.contentHeight,
    required this.scrollOffset,
    required this.viewportExtent,
    required this.trackColor,
    required this.viewportColor,
    required this.addColor,
    required this.removeColor,
    required this.modifyColor,
  });

  final List<DiffBlock> blocks;
  final int totalRows;
  final double lineHeight;
  final double topPadding;
  final double contentHeight;
  final double scrollOffset;
  final double viewportExtent;
  final Color trackColor;
  final Color viewportColor;
  final Color addColor;
  final Color removeColor;
  final Color modifyColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (contentHeight <= 0) return;
    final paint = Paint()..style = PaintingStyle.fill;

    // Track background.
    paint.color = trackColor.withValues(alpha: 0.4);
    canvas.drawRect(Offset.zero & size, paint);

    final scale = size.height / contentHeight;

    // Change marks across the whole file.
    for (final block in blocks) {
      final top = (topPadding + block.startRow * lineHeight) * scale;
      final bottom = (topPadding + block.endRow * lineHeight) * scale;
      final markHeight = math.max(2.0, bottom - top);
      paint.color = _colorFor(block.kind).withValues(alpha: 0.85);
      canvas.drawRect(
        Rect.fromLTWH(2, top, size.width - 4, markHeight),
        paint,
      );
    }

    // Viewport indicator.
    if (viewportExtent > 0 && viewportExtent < contentHeight) {
      final vTop = scrollOffset * scale;
      final vHeight = viewportExtent * scale;
      paint.color = viewportColor;
      canvas.drawRect(Rect.fromLTWH(0, vTop, size.width, vHeight), paint);
    }
  }

  Color _colorFor(DiffRowKind kind) => switch (kind) {
        DiffRowKind.insert => addColor,
        DiffRowKind.delete => removeColor,
        _ => modifyColor,
      };

  @override
  bool shouldRepaint(_OverviewRulerPainter old) =>
      old.scrollOffset != scrollOffset ||
      old.contentHeight != contentHeight ||
      old.viewportExtent != viewportExtent ||
      old.totalRows != totalRows ||
      !identical(old.blocks, blocks);
}
