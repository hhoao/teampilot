import 'package:flutter/material.dart';

import '../../services/diff/diff_model.dart';

/// Positions a small apply control (`>>`) at each [DiffBlock]'s vertical center
/// in the side-by-side ribbon gutter.
class DiffHunkApplyGutter extends StatelessWidget {
  const DiffHunkApplyGutter({
    required this.blocks,
    required this.scrollOffset,
    required this.lineHeight,
    required this.topPadding,
    required this.onApply,
    required this.tooltip,
    super.key,
  });

  final List<DiffBlock> blocks;
  final double scrollOffset;
  final double lineHeight;
  final double topPadding;
  final ValueChanged<DiffBlock> onApply;
  final String tooltip;

  static const double _buttonHeight = 20;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        for (final block in blocks)
          if (_isVisible(block))
            Positioned(
              left: 0,
              right: 0,
              top: _blockCenterY(block) - _buttonHeight / 2,
              height: _buttonHeight,
              child: Tooltip(
                message: tooltip,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: Key('diff-apply-hunk-${block.startRow}'),
                    onTap: () => onApply(block),
                    child: const Center(
                      child: Text(
                        '>>',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }

  bool _isVisible(DiffBlock block) {
    final topY = topPadding - scrollOffset + block.startRow * lineHeight;
    final botY = topPadding - scrollOffset + block.endRow * lineHeight;
    return botY - topY >= 0.5;
  }

  double _blockCenterY(DiffBlock block) {
    final topY = topPadding - scrollOffset + block.startRow * lineHeight;
    final botY = topPadding - scrollOffset + block.endRow * lineHeight;
    return (topY + botY) / 2;
  }
}
