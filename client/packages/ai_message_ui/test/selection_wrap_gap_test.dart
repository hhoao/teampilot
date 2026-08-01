import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Documents why chat selection can still show a hairline between wrapped
/// lines after [BoxHeightStyle.includeLineSpacingTop]: Skia boxes only
/// overlap by ~0.1px, which snaps to an abutting edge under common DPRs.
void main() {
  testWidgets('includeLineSpacingTop leaves sub-pixel wrap gaps', (tester) async {
    const style = TextStyle(fontSize: 14, height: 1.65);
    const text = 'updateAwaitingAssistant, 未匹配的 optimistic pending';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              child: DefaultSelectionStyle(
                selectionHeightStyle: ui.BoxHeightStyle.includeLineSpacingTop,
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

    final paragraph = tester.renderObject<RenderParagraph>(find.byType(RichText));
    expect(paragraph.selectionHeightStyle, ui.BoxHeightStyle.includeLineSpacingTop);

    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
      boxHeightStyle: paragraph.selectionHeightStyle,
    );
    expect(boxes.length, greaterThan(1));

    final rects = boxes.map((b) => b.toRect()).toList()
      ..sort((a, b) => a.top.compareTo(b.top));

    // Not the old 9px tight gap — line boxes nearly abut / barely overlap.
    for (var i = 1; i < rects.length; i++) {
      final gap = rects[i].top - rects[i - 1].bottom;
      expect(gap.abs(), lessThan(1.0), reason: 'pair $i gap=$gap');
    }

    // DPR snap turns ~0.1 overlap into a zero gap (AA hairline risk).
    const dpr = 2.0;
    double snap(double v) => (v * dpr).round() / dpr;
    final snappedGaps = <double>[];
    for (var i = 1; i < rects.length; i++) {
      snappedGaps.add(snap(rects[i].top) - snap(rects[i - 1].bottom));
    }
    expect(
      snappedGaps.any((g) => g >= 0),
      isTrue,
      reason: 'at least one abutting edge after snap: $snappedGaps',
    );
  });
}
