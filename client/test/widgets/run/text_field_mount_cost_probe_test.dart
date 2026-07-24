import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Cold-mount probe. Run each case in a **separate process** so the first
/// [TextField] does not warm later cases:
///
/// ```bash
/// flutter test test/widgets/run/text_field_mount_cost_probe_test.dart --name cold_one_text_field
/// flutter test test/widgets/run/text_field_mount_cost_probe_test.dart --name cold_six_text_fields
/// flutter test test/widgets/run/text_field_mount_cost_probe_test.dart --name cold_multiline_text_field
/// flutter test test/widgets/run/text_field_mount_cost_probe_test.dart --name cold_code_editor
/// ```
void main() {
  Future<void> _warmShell(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    await tester.pump();
  }

  Future<int> _mountBody(WidgetTester tester, Widget body) async {
    await _warmShell(tester);
    final sw = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: body),
        ),
      ),
    );
    await tester.pump();
    sw.stop();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 200));
    // ignore: avoid_print — probe output
    print('mount_ms=${sw.elapsedMilliseconds}');
    return sw.elapsedMilliseconds;
  }

  testWidgets('cold_one_text_field', (tester) async {
    await _mountBody(
      tester,
      const TextField(decoration: InputDecoration(labelText: 'a')),
    );
  });

  testWidgets('cold_six_text_fields', (tester) async {
    await _mountBody(
      tester,
      Column(
        children: [
          for (var i = 0; i < 6; i++)
            TextField(decoration: InputDecoration(labelText: 'f$i')),
        ],
      ),
    );
  });

  testWidgets('cold_multiline_text_field', (tester) async {
    await _mountBody(
      tester,
      const TextField(
        maxLines: 3,
        decoration: InputDecoration(labelText: 'multi'),
      ),
    );
  });

  testWidgets('cold_code_editor', (tester) async {
    await _mountBody(
      tester,
      CodeEditor(
        controller: CodeLineEditingController.fromText(''),
        wordWrap: true,
        autofocus: false,
      ),
    );
  });
}
