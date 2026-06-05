import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/diff/diff_decoration_mapper.dart';
import 'package:teampilot/services/diff/diff_model.dart';
import 'package:teampilot/widgets/diff/diff_ribbon_painter.dart';

const _colors = DiffColors(
  addBand: Color(0x222EA043),
  addInline: Color(0x552EA043),
  removeBand: Color(0x22FF0000),
  removeInline: Color(0x55FF0000),
  fillerBand: Color(0x11000000),
  ribbonAdd: Color(0x332EA043),
  ribbonRemove: Color(0x33FF0000),
  ribbonModify: Color(0x330000FF),
);

DiffRibbonPainter _painter({
  double scrollOffset = 0,
  double lineHeight = 16,
  List<DiffBlock> blocks = const [],
}) =>
    DiffRibbonPainter(
      scrollOffset: scrollOffset,
      lineHeight: lineHeight,
      topPadding: 5,
      blocks: blocks,
      colors: _colors,
    );

void main() {
  const blocks = [
    DiffBlock(startRow: 2, endRow: 4, kind: DiffRowKind.modify),
  ];

  group('DiffRibbonPainter.shouldRepaint', () {
    test('repaints when scroll offset changes', () {
      expect(
        _painter(scrollOffset: 10).shouldRepaint(_painter(scrollOffset: 0)),
        isTrue,
      );
    });

    test('repaints when blocks change', () {
      expect(
        _painter(blocks: blocks).shouldRepaint(_painter(blocks: const [])),
        isTrue,
      );
    });

    test('does not repaint when nothing changed', () {
      expect(
        _painter(blocks: blocks, scrollOffset: 8)
            .shouldRepaint(_painter(blocks: blocks, scrollOffset: 8)),
        isFalse,
      );
    });
  });

  group('DiffRibbonPainter.paint', () {
    void paintInto(DiffRibbonPainter painter) {
      final recorder = PictureRecorder();
      painter.paint(Canvas(recorder), const Size(24, 400));
      recorder.endRecording().dispose();
    }

    test('paints blocks without error', () {
      paintInto(_painter(blocks: blocks));
    });

    test('no-ops with empty blocks or non-positive line height', () {
      paintInto(_painter());
      paintInto(_painter(blocks: blocks, lineHeight: 0));
    });

    test('skips blocks scrolled out of view', () {
      // Block at rows 2..4 with a huge scroll offset is above the viewport.
      paintInto(_painter(blocks: blocks, scrollOffset: 100000));
    });
  });
}
