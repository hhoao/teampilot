import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// [BoxHeightStyle.includeLineSpacingMiddle] keeps wrap line-boxes nearly
/// abutting (not tight’s ~9px gap). Unlike [BoxHeightStyle.includeLineSpacingTop],
/// Middle often retains a usable negative gap after common DPR snaps.
void main() {
  testWidgets('includeLineSpacingMiddle covers wrap line spacing', (
    tester,
  ) async {
    const style = TextStyle(fontSize: 14, height: 1.65);
    const text = 'updateAwaitingAssistant, 未匹配的 optimistic pending';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              child: DefaultSelectionStyle(
                selectionHeightStyle:
                    ui.BoxHeightStyle.includeLineSpacingMiddle,
                child: SelectionArea(
                  child: const Text(text, style: style),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText),
    );
    expect(
      paragraph.selectionHeightStyle,
      ui.BoxHeightStyle.includeLineSpacingMiddle,
    );

    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
      boxHeightStyle: paragraph.selectionHeightStyle,
    );
    expect(boxes.length, greaterThan(1));

    final rects = boxes.map((b) => b.toRect()).toList()
      ..sort((a, b) => a.top.compareTo(b.top));

    // Not the old 9px tight gap — line boxes nearly abut / overlap.
    for (var i = 1; i < rects.length; i++) {
      final gap = rects[i].top - rects[i - 1].bottom;
      expect(gap.abs(), lessThan(1.0), reason: 'pair $i gap=$gap');
    }

    // Middle typically keeps overlap after 2x snap (Top often abutted at 0).
    const dpr = 2.0;
    double snap(double v) => (v * dpr).round() / dpr;
    for (var i = 1; i < rects.length; i++) {
      final snappedGap =
          snap(rects[i].top) - snap(rects[i - 1].bottom);
      expect(
        snappedGap,
        lessThan(0),
        reason: 'pair $i should still overlap after snap: $snappedGap',
      );
    }
  });
}
