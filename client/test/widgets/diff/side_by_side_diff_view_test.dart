import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:teampilot/services/diff/diff_engine.dart';
import 'package:teampilot/widgets/diff/side_by_side_diff_view.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUpAll(setUpTestAppStorage);
  tearDownAll(tearDownTestAppStorage);

  Future<void> pump(
    WidgetTester tester, {
    required String oldText,
    required String newText,
    String? filePath,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 400,
          child: SideBySideDiffView(
            result: computeLineDiff(oldText, newText),
            filePath: filePath,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('renders two code editors for a modification', (tester) async {
    await pump(
      tester,
      oldText: 'final a = 1;\nfinal b = 2;\nfinal c = 3;',
      newText: 'final a = 1;\nfinal b = 22;\nfinal c = 3;',
      filePath: 'sample.dart',
    );

    expect(find.byType(CodeEditor), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('handles pure insertion and deletion without error',
      (tester) async {
    await pump(tester, oldText: 'a\nc', newText: 'a\nb\nc');
    expect(tester.takeException(), isNull);

    await pump(tester, oldText: 'a\nb\nc', newText: 'a\nc');
    expect(tester.takeException(), isNull);
  });

  testWidgets('updates when inputs change', (tester) async {
    await pump(tester, oldText: 'x', newText: 'y');
    await pump(tester, oldText: 'hello', newText: 'hello world');
    expect(tester.takeException(), isNull);
  });
}
