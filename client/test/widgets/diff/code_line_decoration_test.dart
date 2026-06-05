import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Verifies the vendored re-editor patch: [CodeEditor.lineDecorations] +
/// [CodeLineDecoration] compile, render, and repaint without error.
void main() {
  Future<void> pumpEditor(
    WidgetTester tester,
    List<CodeLineDecoration> decorations,
  ) async {
    final controller =
        CodeLineEditingController.fromText('line one\nline two\nline three');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 300,
          child: CodeEditor(
            controller: controller,
            readOnly: true,
            showCursorWhenReadOnly: false,
            indicatorBuilder: (context, editingController, chunkController, notifier) =>
                const SizedBox.shrink(),
            lineDecorations: decorations,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('full-line band decoration renders without error', (tester) async {
    await pumpEditor(tester, const [
      CodeLineDecoration(
        selection: CodeLineSelection.collapsed(index: 1, offset: 0),
        color: Color(0x332EA043),
        fillLine: true,
      ),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inline range decoration renders without error', (tester) async {
    await pumpEditor(tester, const [
      CodeLineDecoration(
        selection: CodeLineSelection(
          baseIndex: 0,
          baseOffset: 0,
          extentIndex: 0,
          extentOffset: 4,
        ),
        color: Color(0x55FF5555),
      ),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('updating decorations repaints without error', (tester) async {
    await pumpEditor(tester, const [
      CodeLineDecoration(
        selection: CodeLineSelection.collapsed(index: 0, offset: 0),
        color: Color(0x332EA043),
        fillLine: true,
      ),
    ]);
    await pumpEditor(tester, const [
      CodeLineDecoration(
        selection: CodeLineSelection.collapsed(index: 2, offset: 0),
        color: Color(0x33FF5555),
        fillLine: true,
      ),
    ]);
    expect(tester.takeException(), isNull);
  });

  test('CodeLineDecoration value equality', () {
    const a = CodeLineDecoration(
      selection: CodeLineSelection.collapsed(index: 1, offset: 0),
      color: Color(0x332EA043),
      fillLine: true,
    );
    const b = CodeLineDecoration(
      selection: CodeLineSelection.collapsed(index: 1, offset: 0),
      color: Color(0x332EA043),
      fillLine: true,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
