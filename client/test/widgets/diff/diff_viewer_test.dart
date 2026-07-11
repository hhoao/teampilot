import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/widgets/diff/diff_toolbar.dart';
import 'package:teampilot/widgets/diff/diff_viewer.dart';
import 'package:teampilot/widgets/diff/side_by_side_diff_view.dart';
import 'package:teampilot/widgets/diff/unified_diff_view.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUpAll(setUpTestAppStorage);
  tearDownAll(tearDownTestAppStorage);

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 400,
            child: DiffViewer.fromTexts(
              oldText: 'final a = 1;\nfinal b = 2;',
              newText: 'final a = 1;\nfinal b = 22;\nfinal c = 3;',
              filePath: 'sample.dart',
            ),
          ),
        ),
      ),
    );
    // Settle the async DocumentSession open + viewport colorize (fires the
    // frame-budget timer) so no timer outlives the test body.
    await tester.pumpAndSettle();
  }

  testWidgets('renders toolbar over a side-by-side body by default', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(DiffToolbar), findsOneWidget);
    expect(find.byType(SideBySideDiffView), findsOneWidget);
    expect(find.byType(UnifiedDiffView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches to unified layout', (tester) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.view_agenda_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(UnifiedDiffView), findsOneWidget);
    expect(find.byType(SideBySideDiffView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('toggling ignore whitespace does not throw', (tester) async {
    await pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.diffIgnoreWhitespace));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('next-change navigation does not throw', (tester) async {
    await pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.byTooltip(l10n.diffNextChange));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'fromUnifiedDiff renders and hides ignore-ws without a reloader',
    (tester) async {
      const diff = '''
--- a/f.dart
+++ b/f.dart
@@ -1,2 +1,2 @@
 final a = 1;
-final b = 2;
+final b = 22;
''';
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: DiffViewer.fromUnifiedDiff(
                diffText: diff,
                filePath: 'f.dart',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.byType(SideBySideDiffView), findsOneWidget);
      // No reloader => ignore-whitespace chip is hidden.
      expect(find.text(l10n.diffIgnoreWhitespace), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'fromUnifiedDiff remounts when key changes for a different file',
    (tester) async {
      const first = '''
--- a/a.dart
+++ b/a.dart
@@ -1 +1 @@
-old-a
+new-a
''';
      const second = '''
--- a/b.dart
+++ b/b.dart
@@ -1 +1 @@
-old-b
+new-b
''';
      Future<void> pumpDiff(String diff, String path) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 400,
                child: DiffViewer.fromUnifiedDiff(
                  key: ValueKey(path),
                  diffText: diff,
                  filePath: path,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpDiff(first, 'a.dart');
      expect(find.byType(DiffViewer), findsOneWidget);
      expect(
        tester.widget<DiffViewer>(find.byType(DiffViewer)).filePath,
        'a.dart',
      );

      await pumpDiff(second, 'b.dart');
      expect(
        tester.widget<DiffViewer>(find.byType(DiffViewer)).filePath,
        'b.dart',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
