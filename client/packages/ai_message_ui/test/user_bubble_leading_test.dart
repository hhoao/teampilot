import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

void main() {
  test('userBubble style uses even leading distribution', () {
    final style = MarkdownTokens.test().userBubble(Colors.black);
    expect(style.leadingDistribution, TextLeadingDistribution.even);
  });

  testWidgets('short user bubble optical padding is vertically even', (
    tester,
  ) async {
    const text = '提交吧';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageView(
            showActionBar: false,
            message: const AiMessage(
              id: 'u1',
              role: AiRole.user,
              parts: [AiTextPart(text: text)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bubbleFinder = find.ancestor(
      of: find.text(text),
      matching: find.byType(ColoredBox),
    );
    final bubble = tester.getRect(bubbleFinder.first);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: bubbleFinder.first, matching: find.byType(RichText)),
    );
    expect(
      paragraph.text.style?.leadingDistribution,
      TextLeadingDistribution.even,
    );
    expect(paragraph.textHeightBehavior?.applyHeightToFirstAscent, isFalse);
    expect(paragraph.textHeightBehavior?.applyHeightToLastDescent, isFalse);

    final boxes = paragraph.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    expect(boxes, isNotEmpty);
    var inkTop = boxes.first.toRect().top;
    var inkBottom = boxes.first.toRect().bottom;
    for (final box in boxes.skip(1)) {
      final rect = box.toRect();
      if (rect.top < inkTop) inkTop = rect.top;
      if (rect.bottom > inkBottom) inkBottom = rect.bottom;
    }
    final topGap = paragraph.localToGlobal(Offset(0, inkTop)).dy - bubble.top;
    final bottomGap =
        bubble.bottom - paragraph.localToGlobal(Offset(0, inkBottom)).dy;
    expect(
      topGap,
      closeTo(bottomGap, 1.0),
      reason: 'top $topGap vs bottom $bottomGap',
    );
  });
}
