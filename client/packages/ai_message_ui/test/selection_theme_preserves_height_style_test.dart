import 'dart:ui' as ui;

import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'nested Theme keeps AiLineSpacedSelectionStyle selectionHeightStyle',
    (tester) async {
      const text = 'AI Agent 封装的面向团队易用的桌面客提示词、乃至不同的 CLI，按角色分档';
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [AiMessageTheme.test()],
          ),
          home: Scaffold(
            body: AiLineSpacedSelectionStyle(
              child: SelectionArea(
                child: Builder(
                  builder: (context) {
                    // Mirrors session_chat_view: local Theme() for AiMessageTheme.
                    return Theme(
                      data: Theme.of(context).copyWith(
                        extensions: [
                          ...Theme.of(context).extensions.values.where(
                            (e) => e is! AiMessageTheme,
                          ),
                          AiMessageTheme.of(context).copyWith(messageSpacing: 8),
                        ],
                      ),
                      child: const SizedBox(
                        width: 280,
                        child: Text(
                          text,
                          style: TextStyle(fontSize: 14, height: 1.65),
                        ),
                      ),
                    );
                  },
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
        ui.BoxHeightStyle.includeLineSpacingTop,
      );

      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length),
        boxHeightStyle: paragraph.selectionHeightStyle,
      );
      final rects = boxes.map((b) => b.toRect()).toList()
        ..sort((a, b) => a.top.compareTo(b.top));
      expect(rects.length, greaterThan(1));
      for (var i = 1; i < rects.length; i++) {
        final gap = rects[i].top - rects[i - 1].bottom;
        // tight would be ~+9px; includeLineSpacing* is ~-0.1.
        expect(gap, lessThan(1.0), reason: 'pair $i still has tight-sized gap');
      }
    },
  );
}
