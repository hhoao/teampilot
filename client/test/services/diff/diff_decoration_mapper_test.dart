import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/diff/diff_decoration_mapper.dart';
import 'package:teampilot/services/diff/diff_engine.dart';

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

void main() {
  group('buildDiffPaneTexts', () {
    test('both panes have equal visual line count with blank fillers', () {
      final rows = computeLineDiff('a\nc', 'a\nb\nc').rows;
      final texts = buildDiffPaneTexts(rows);

      final leftLines = texts.leftText.split('\n');
      final rightLines = texts.rightText.split('\n');
      expect(leftLines.length, rightLines.length);
      expect(leftLines.length, rows.length);
      // The inserted 'b' has a blank filler on the left.
      expect(leftLines.contains(''), isTrue);
      expect(rightLines.contains('b'), isTrue);
    });

    test('line numbers are null on filler rows', () {
      final rows = computeLineDiff('a\nc', 'a\nb\nc').rows;
      final texts = buildDiffPaneTexts(rows);
      // Some left number is null (the filler opposite the insert).
      expect(texts.leftNumbers.contains(null), isTrue);
      // Right side numbers are all present (pure insertion).
      expect(texts.rightNumbers.every((n) => n != null), isTrue);
    });
  });

  group('buildUnifiedPane', () {
    test('modify row expands to an old line then a new line', () {
      final rows = computeLineDiff('value old', 'value new').rows;
      final pane = buildUnifiedPane(rows, _colors);
      final lines = pane.text.split('\n');

      expect(lines, ['value old', 'value new']);
      expect(pane.numbers, [1, 1]);
      // One change block beginning at unified line 0.
      expect(pane.blockStartLines, [0]);
    });

    test('context lines carry numbers and no decorations', () {
      final rows = computeLineDiff('a\nb', 'a\nB').rows;
      final pane = buildUnifiedPane(rows, _colors);
      // Line 0 is context 'a' with no band.
      expect(pane.text.split('\n').first, 'a');
      final line0Decorations =
          pane.decorations.where((d) => d.selection.baseIndex == 0);
      expect(line0Decorations, isEmpty);
    });

    test('separate changes produce separate block starts', () {
      final rows = computeLineDiff('a\nb\nc\nd\ne', 'a\nB\nc\nd\nE').rows;
      final pane = buildUnifiedPane(rows, _colors);
      expect(pane.blockStartLines.length, 2);
    });
  });

  group('buildDiffPaneDecorations', () {
    test('equal rows produce no decorations', () {
      final rows = computeLineDiff('a\nb', 'a\nb').rows;
      final deco = buildDiffPaneDecorations(rows, _colors);
      expect(deco.left, isEmpty);
      expect(deco.right, isEmpty);
    });

    test('insert puts an add band right and a filler band left', () {
      final rows = computeLineDiff('a', 'a\nb').rows;
      final deco = buildDiffPaneDecorations(rows, _colors);

      expect(deco.right.any((d) => d.fillLine && d.color == _colors.addBand),
          isTrue);
      expect(deco.left.any((d) => d.fillLine && d.color == _colors.fillerBand),
          isTrue);
    });

    test('modify row has bands plus inline ranges on the changed side', () {
      final rows = computeLineDiff('LABEL, REMARK', 'LABEL, REMARK, LEVEL').rows;
      final deco = buildDiffPaneDecorations(rows, _colors);

      // Right gets the add band + at least one non-fillLine inline range.
      expect(deco.right.any((d) => d.fillLine && d.color == _colors.addBand),
          isTrue);
      final inline = deco.right.where((d) => !d.fillLine).toList();
      expect(inline, isNotEmpty);
      expect(inline.first.color, _colors.addInline);
      // Inline range is intra-line (single line index).
      expect(inline.first.selection.baseIndex, inline.first.selection.extentIndex);
    });
  });
}
