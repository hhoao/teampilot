import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_search_content_section.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_search_dialog.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_search_widgets.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/search/workspace_search_indexes.dart';

import '../../../support/post_frame_test_harness.dart';

void main() {
  late Directory fixture;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('tp_dialog_content_');
    File('${fixture.path}/a.dart').writeAsStringSync('hello world\n');
    File('${fixture.path}/b.txt').writeAsStringSync('hello text\n');
  });

  tearDown(() {
    if (fixture.existsSync()) fixture.deleteSync(recursive: true);
  });

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold)));

  Widget wrapSection({
    required void Function(String path) onOpenFile,
    required String root,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        // Expanded mirrors the dialog's bounded results area (Flexible/Expanded
        // under the dialog shell) so the section's internal shrink-wrapped
        // list can scroll instead of growing unbounded.
        body: Column(
          children: [
            Expanded(
              child: WorkspaceSearchContentSection(
                root: root,
                fs: LocalFilesystem(),
                onOpenFile: onOpenFile,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Types a query in the content section, fires the 300ms debounce, then
  /// drains the engine stream.
  Future<void> runSearch(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField).first, query);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'content filter runs a real search and lists file:line rows',
    (tester) async {
      await tester.pumpWidget(wrapSection(onOpenFile: (_) {}, root: fixture.path));
      await runSearch(tester, 'hello');
      expect(find.textContaining('a.dart:1'), findsOneWidget);
      expect(find.textContaining('b.txt:1'), findsOneWidget);
      // The line preview is the row's relative-path subtitle.
      expect(find.text('hello world'), findsOneWidget);
      expect(find.text('hello text'), findsOneWidget);
    },
  );

  testWidgets('tapping a content row invokes onOpenFile with the file path', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      wrapSection(onOpenFile: opened.add, root: fixture.path),
    );
    await runSearch(tester, 'hello');
    // Tap the row that renders the a.dart name — the row's own onOpenFile
    // callback carries that row's match path, so the hit test is unambiguous.
    final rowFinder = find.ancestor(
      of: find.textContaining('a.dart:1'),
      matching: find.byType(WorkspaceSearchFileRow),
    );
    await tester.tap(rowFinder.first);
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
    expect(opened.single, endsWith('a.dart'));
  });

  testWidgets('empty query shows the empty hint', (tester) async {
    await tester.pumpWidget(wrapSection(onOpenFile: (_) {}, root: fixture.path));
    final l10n = l10nOf(tester);
    expect(find.text(l10n.workspaceSearchEmptyHint), findsOneWidget);

    await runSearch(tester, 'hello');
    expect(find.textContaining('a.dart:1'), findsOneWidget);

    await runSearch(tester, '');
    expect(find.text(l10n.workspaceSearchEmptyHint), findsOneWidget);
    expect(find.textContaining('a.dart:1'), findsNothing);
  });

  testWidgets('query with surrounding whitespace is trimmed before searching', (
    tester,
  ) async {
    await tester.pumpWidget(wrapSection(onOpenFile: (_) {}, root: fixture.path));
    await runSearch(tester, '  hello  ');
    expect(find.textContaining('a.dart:1'), findsOneWidget);
    expect(find.textContaining('b.txt:1'), findsOneWidget);
  });

  testWidgets('whitespace-only query shows the empty hint', (tester) async {
    await tester.pumpWidget(wrapSection(onOpenFile: (_) {}, root: fixture.path));
    final l10n = l10nOf(tester);
    await runSearch(tester, '   ');
    expect(find.text(l10n.workspaceSearchEmptyHint), findsOneWidget);
    expect(find.byType(WorkspaceSearchFileRow), findsNothing);
  });

  testWidgets('results are capped at 500 with a truncation hint', (tester) async {
    File('${fixture.path}/big.txt').writeAsStringSync(
      List.generate(600, (i) => 'match line $i\n').join(),
    );
    await tester.pumpWidget(wrapSection(onOpenFile: (_) {}, root: fixture.path));
    final l10n = l10nOf(tester);
    await runSearch(tester, 'match');
    // The lazy list only builds visible rows; the cap keeps that extent
    // bounded. Scroll to the tail to reveal the truncation hint. The first
    // Scrollable is the TextField's own; the results list is the last.
    final resultsList = find.byType(Scrollable).last;
    await tester.dragUntilVisible(
      find.text(l10n.workspaceSearchTruncated),
      resultsList,
      const Offset(0, -1000),
    );
    expect(find.text(l10n.workspaceSearchTruncated), findsOneWidget);
    // The engine stopped at the 500th match: the last row is big.txt:500 and
    // no later line exists.
    expect(find.textContaining('big.txt:500'), findsWidgets);
    expect(find.textContaining('big.txt:501'), findsNothing);
  });

  testWidgets('invalid regex shows no-results instead of crashing', (
    tester,
  ) async {
    await tester.pumpWidget(wrapSection(onOpenFile: (_) {}, root: fixture.path));
    final l10n = l10nOf(tester);
    await runSearch(tester, '[unclosed');
    expect(tester.takeException(), isNull);
    expect(find.text(l10n.workspaceSearchNoResults), findsOneWidget);
  });

  testWidgets(
    'dialog content filter shows only the content section; all hides it',
    (tester) async {
      setUpTestAppStorage();
      addTearDown(tearDownTestAppStorage);
      final workspace = Workspace(
        workspaceId: 'ws-content',
        folders: [WorkspaceFolder(path: fixture.path)],
        createdAt: 0,
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: WorkspaceSearchDialog(
              workspace: workspace,
              sessions: const [],
              indexes: WorkspaceSearchIndexes(),
              fs: LocalFilesystem(),
              emptyTitleFallback: 'New Chat',
              onOpenSession: (_) async {},
              onOpenFile: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = l10nOf(tester);

      // All mode: no content section.
      expect(find.byType(WorkspaceSearchContentSection), findsNothing);

      await tester.tap(find.text(l10n.workspaceSearchContent));
      await tester.pumpAndSettle();
      expect(find.byType(WorkspaceSearchContentSection), findsOneWidget);
      // Content mode is exclusive: no conversation/file sections are shown.
      expect(find.byType(ListView), findsNothing);

      await tester.tap(find.text(l10n.workspaceSearchFilterAll));
      await tester.pumpAndSettle();
      expect(find.byType(WorkspaceSearchContentSection), findsNothing);
    },
  );
}
