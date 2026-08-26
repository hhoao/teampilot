import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/l10n_extensions.dart';
import 'package:teampilot/services/editor/markdown_preview_find_controller.dart';
import 'package:teampilot/widgets/find/find_bar_widgets.dart';
import 'package:teampilot/widgets/workbench/markdown_preview_find_bar.dart';
import 'package:tp_markdown/tp_markdown.dart';

Future<MarkdownPreviewFindController> pumpBar(WidgetTester tester) async {
  final controller = MarkdownPreviewFindController()
    ..openFind()
    ..setDocument(compileMarkdown('one two three two\n'));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: MarkdownPreviewFindBar(controller: controller),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.enterText(find.byType(TextField), 'two');
  await tester.pump(const Duration(milliseconds: 200));
  return controller;
}

void main() {
  testWidgets('typing populates counter; enter advances', (tester) async {
    final controller = await pumpBar(tester);
    expect(controller.hits.length, 2);
    expect(find.textContaining('1/2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.activeIndex, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(controller.activeIndex, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(controller.open, isFalse);
    expect(controller.hits, isEmpty);
    controller.dispose();
  });

  testWidgets('no-match shows muted No matches', (tester) async {
    final controller = await pumpBar(tester);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 200));
    final l10n = AppLocalizations.of(
      tester.element(find.byType(MarkdownPreviewFindBar)),
    );
    expect(find.byType(FindCounterText), findsOneWidget);
    expect(find.text(l10n.editorFindNoResults), findsOneWidget);
    // Prev/next disabled without hits; close stays available.
    expect(controller.counterLabel(), isEmpty);
    controller.next();
    controller.previous();
    expect(controller.activeIndex, -1);
    controller.dispose();
  });

  testWidgets('seeds the field text from an existing query', (tester) async {
    final controller = MarkdownPreviewFindController()
      ..openFind()
      ..search('two');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: MarkdownPreviewFindBar(controller: controller),
          ),
        ),
      ),
    );
    // Settle the pending debounce scan so no timer leaks into teardown.
    await tester.pump(const Duration(milliseconds: 200));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'two');
  });
}
