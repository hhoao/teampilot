import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../services/diff/diff_decoration_mapper.dart';
import '../../services/diff/diff_model.dart';

/// Paints the center-gutter ribbon connecting each [DiffBlock]'s change region
/// across the two panes.
///
/// Both panes are filler-aligned (same line index per row) and scroll together,
/// so a block occupies the same y-range on both sides — the connector is a band
/// spanning the gap. Positions are derived from [scrollOffset] and an exact
/// [lineHeight] (computed with the same TextPainter the editor uses), so the
/// ribbon stays pixel-aligned with the text without reading editor internals.
class DiffRibbonPainter extends CustomPainter {
  DiffRibbonPainter({
    required this.scrollOffset,
    required this.lineHeight,
    required this.topPadding,
    required this.blocks,
    required this.colors,
  });

  final double scrollOffset;
  final double lineHeight;

  /// The editor's content top inset (re-editor's default field padding).
  final double topPadding;

  final List<DiffBlock> blocks;
  final DiffColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (blocks.isEmpty || lineHeight <= 0) {
      return;
    }
    // Never paint outside the gutter bounds, even for blocks taller than the
    // viewport.
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()..style = PaintingStyle.fill;
    for (final block in blocks) {
      final double topY = topPadding - scrollOffset + block.startRow * lineHeight;
      final double botY = topPadding - scrollOffset + block.endRow * lineHeight;
      final double top = topY.clamp(0.0, size.height);
      final double bot = botY.clamp(0.0, size.height);
      if (bot - top < 0.5) {
        continue;
      }
      paint.color = _colorFor(block.kind);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0, top, size.width, bot),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  Color _colorFor(DiffRowKind kind) => switch (kind) {
        DiffRowKind.insert => colors.ribbonAdd,
        DiffRowKind.delete => colors.ribbonRemove,
        _ => colors.ribbonModify,
      };

  @override
  bool shouldRepaint(DiffRibbonPainter old) =>
      old.scrollOffset != scrollOffset ||
      old.lineHeight != lineHeight ||
      old.topPadding != topPadding ||
      old.colors != colors ||
      !listEquals(old.blocks, blocks);
}
