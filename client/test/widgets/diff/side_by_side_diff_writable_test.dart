import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/diff/diff_engine.dart';
import 'package:teampilot/services/diff/diff_model.dart';
import 'package:teampilot/widgets/diff/diff_viewer.dart';
import 'package:teampilot/widgets/diff/side_by_side_diff_view.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUpAll(setUpTestAppStorage);
  tearDownAll(tearDownTestAppStorage);

  Future<void> pumpSideBySide(
    WidgetTester tester, {
    required DiffResult result,
    bool writable = false,
    String canonicalText = '',
    void Function(String text)? onCanonicalChanged,
    Future<void> Function(DiffResult result, DiffBlock block)? onApplyHunk,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 400,
            child: SideBySideDiffView(
              result: result,
              filePath: 'sample.dart',
              writable: writable,
              canonicalText: canonicalText,
              onCanonicalChanged: onCanonicalChanged,
              onApplyHunk: onApplyHunk,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows apply control when writable and tap invokes callback', (
    tester,
  ) async {
    final result = computeLineDiff('a\nb', 'a');
    DiffBlock? appliedBlock;
    await pumpSideBySide(
      tester,
      result: result,
      writable: true,
      canonicalText: 'a',
      onCanonicalChanged: (_) {},
      onApplyHunk: (r, block) async {
        appliedBlock = block;
      },
    );

    expect(find.text('>>'), findsWidgets);
    await tester.tap(find.text('>>').first);
    await tester.pumpAndSettle();
    expect(appliedBlock, isNotNull);
  });

  testWidgets('hides apply control when not writable', (tester) async {
    final result = computeLineDiff('a\nb', 'a');
    await pumpSideBySide(tester, result: result);
    expect(find.text('>>'), findsNothing);
  });

  testWidgets('unified mode hides apply even when writable flag true', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 400,
            child: DiffViewer.fromTexts(
              oldText: 'a\nb',
              newText: 'a',
              filePath: 'sample.dart',
              writable: true,
              canonicalText: 'a',
              onCanonicalChanged: (_) {},
              onApplyHunk: (_, __) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('>>'), findsNothing);
  });
}
