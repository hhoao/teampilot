import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:teampilot/l10n/l10n_extensions.dart';
import 'package:teampilot/widgets/workbench/code_editor_find_panel.dart';

/// Verifies the workbench file-editor find/replace bar.
///
/// Most tests pump [CodeEditorFindPanel] directly with an explicit `readOnly`
/// so the replace row can be exercised in both modes. Search results arrive on
/// a real isolate (re-editor `_IsolateTasker`), so tests that type a non-empty
/// pattern settle it with `tester.runAsync` before teardown.
void main() {
  Future<CodeFindController> pumpPanel(
    WidgetTester tester, {
    bool readOnly = false,
  }) async {
    final editing = CodeLineEditingController.fromText(
      'hello world\nhello again',
    );
    final ctrl = CodeFindController(editing);
    addTearDown(editing.dispose);
    addTearDown(ctrl.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: CodeEditorFindPanel(controller: ctrl, readOnly: readOnly),
          ),
        ),
      ),
    );
    return ctrl;
  }

  testWidgets('renders nothing while the find bar is closed', (tester) async {
    final ctrl = await pumpPanel(tester);
    expect(find.byType(CodeEditorFindPanel), findsOneWidget);
    // Zero preferred height collapses re-editor's find slot.
    final panel = tester.widget<CodeEditorFindPanel>(
      find.byType(CodeEditorFindPanel),
    );
    expect(panel.preferredSize.height, 0);
    // No find input is rendered.
    expect(find.byType(TextField), findsNothing);
    ctrl.close();
    await tester.pump();
  });

  testWidgets('findMode reveals the find bar and typing sets the pattern', (
    tester,
  ) async {
    final ctrl = await pumpPanel(tester);
    ctrl.findMode();
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'hello');
    await tester.pump();
    expect(ctrl.value!.option.pattern, 'hello');
    expect(ctrl.findInputController.text, 'hello');

    // Settle the isolate-backed search before teardown.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
  });

  testWidgets('shows the match counter after the search completes', (
    tester,
  ) async {
    final ctrl = await pumpPanel(tester);
    ctrl.findMode();
    await tester.pump();
    // Start the search inside the real-async zone: re-editor's isolate-backed
    // search awaits an isolate spawn, whose continuation would stay stuck in
    // FakeAsync if triggered from a widget-tree event.
    await tester.runAsync(() async {
      ctrl.findInputController.text = 'hello';
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    // 'hello' matches twice in "hello world\nhello again".
    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('replace mode adds a replace row', (tester) async {
    final ctrl = await pumpPanel(tester);
    ctrl.findMode();
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);

    ctrl.replaceMode();
    await tester.pump();
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byIcon(Icons.done_all), findsOneWidget);
  });

  testWidgets('read-only files keep the find bar but hide replace', (
    tester,
  ) async {
    final ctrl = await pumpPanel(tester, readOnly: true);
    ctrl.findMode();
    await tester.pump();
    ctrl.replaceMode();
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.done_all), findsNothing);
  });

  testWidgets('CodeEditor wires the find bar through findBuilder', (
    tester,
  ) async {
    final editing = CodeLineEditingController.fromText(
      'hello world\nhello again',
    );
    final ctrl = CodeFindController(editing);
    addTearDown(editing.dispose);
    addTearDown(ctrl.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: CodeEditor(
              controller: editing,
              findController: ctrl,
              // Read-only + no cursor keeps re-editor from scheduling its
              // cursor-blink timer, which would trip the pending-timer check.
              readOnly: true,
              showCursorWhenReadOnly: false,
              findBuilder: (context, controller, ro) =>
                  CodeEditorFindPanel(controller: controller, readOnly: ro),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(CodeEditorFindPanel), findsOneWidget);
    ctrl.findMode();
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
  });
}
