import 'dart:ui' show Brightness;

import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ai_history/workspace_edit_line_highlighter.dart';

void main() {
  const baseStyle = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );

  test('does not throw and returns non-empty span for dart line', () {
    final highlighter = WorkspaceAiEditLineHighlighter(
      brightness: Brightness.dark,
    );

    final span = highlighter.highlight(
      path: 'lib/example.dart',
      text: "final String name = 'hello';",
      kind: AiEditLineKind.add,
      baseStyle: baseStyle,
    );

    expect(span, isA<TextSpan>());
    final textSpan = span as TextSpan;
    expect(textSpan.toPlainText(), "final String name = 'hello';");
    expect(textSpan.children ?? [textSpan], isNotEmpty);
  });

  test('empty text returns plain span', () {
    final highlighter = WorkspaceAiEditLineHighlighter(
      brightness: Brightness.light,
    );

    final span = highlighter.highlight(
      path: 'lib/example.dart',
      text: '',
      kind: AiEditLineKind.context,
      baseStyle: baseStyle,
    );

    expect(span, isA<TextSpan>());
    expect((span as TextSpan).text, '');
  });

  test('merges theme color only — keeps base mono shape fingerprint', () {
    final highlighter = WorkspaceAiEditLineHighlighter(
      brightness: Brightness.dark,
    );

    final span = highlighter.highlight(
      path: 'lib/example.dart',
      text: '// cold italic would stall expand',
      kind: AiEditLineKind.context,
      baseStyle: baseStyle,
    );

    void assertShape(InlineSpan node) {
      if (node is! TextSpan) return;
      final style = node.style;
      if (style != null) {
        expect(style.fontFamily, baseStyle.fontFamily);
        expect(style.fontSize, baseStyle.fontSize);
        expect(style.fontWeight, baseStyle.fontWeight);
        expect(
          style.fontStyle ?? FontStyle.normal,
          FontStyle.normal,
          reason: 'mono italic is not boot-warmed; comments must color-only',
        );
      }
      for (final child in node.children ?? const <InlineSpan>[]) {
        assertShape(child);
      }
    }

    assertShape(span);
  });
}
