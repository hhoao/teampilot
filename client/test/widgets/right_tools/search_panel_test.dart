import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/cubits/content_search/content_search_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/search/content_search_runner.dart';
import 'package:teampilot/services/search/content_replacer.dart';
import 'package:teampilot/widgets/right_tools/search_panel.dart';

void main() {
  late Directory fixture;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('tp_panel_');
    File('${fixture.path}/a.dart').writeAsStringSync('hello world\n');
    File('${fixture.path}/b.dart').writeAsStringSync('nothing\n');
  });

  tearDown(() => fixture.deleteSync(recursive: true));

  ContentSearchCubit buildCubit() => ContentSearchCubit(
    runnerFactory: (o) =>
        ContentSearchRunner(fs: LocalFilesystem(), root: fixture.path),
    replacerFactory: () => ContentReplacer(fs: LocalFilesystem()),
  );

  Widget wrap(ContentSearchCubit cubit, {WorkspaceSearchPanel? panel}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: BlocProvider.value(
        value: cubit,
        child: Scaffold(
          body:
              panel ??
              WorkspaceSearchPanel(
                workspaceId: 'ws1',
                root: fixture.path,
                fs: LocalFilesystem(),
                focusRequest: ValueNotifier<int>(0),
              ),
        ),
      ),
    );
  }

  /// Types a query, fires the debounce, then drains the engine stream.
  Future<void> runSearch(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField).first, query);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'entering a query runs a real rust search and renders file rows',
    (tester) async {
      final cubit = buildCubit();
      addTearDown(cubit.close);
      await tester.pumpWidget(wrap(cubit));
      await runSearch(tester, 'hello');
      expect(find.textContaining('a.dart'), findsWidgets);
      expect(find.textContaining('hello world'), findsWidgets);
      expect(cubit.state.searching, isFalse);
    },
  );

  testWidgets('clicking a result row opens the editor with a line selection', (
    tester,
  ) async {
    String? openedPath;
    int? openedLine;
    final cubit = buildCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      wrap(
        cubit,
        panel: WorkspaceSearchPanel(
          workspaceId: 'ws1',
          root: fixture.path,
          fs: LocalFilesystem(),
          focusRequest: ValueNotifier<int>(0),
          onOpenResult: (path, line) {
            openedPath = path;
            openedLine = line;
          },
        ),
      ),
    );
    await runSearch(tester, 'hello');
    await tester.tap(find.textContaining('hello world').first);
    await tester.pumpAndSettle();
    expect(openedPath, endsWith('a.dart'));
    expect(openedLine, 1);
  });

  testWidgets('replace all applies through the confirm dialog', (tester) async {
    final cubit = buildCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(wrap(cubit));
    await runSearch(tester, 'hello');
    expect(find.textContaining('hello world'), findsWidgets);

    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    await tester.enterText(find.byType(TextField).at(3), 'hi');
    await tester.pump();
    await tester.tap(find.text(l10n.workspaceSearchReplaceAll).first);
    await tester.pumpAndSettle();
    expect(find.text(l10n.workspaceSearchReplaceAllTitle), findsOneWidget);
    await tester.tap(find.text(l10n.workspaceSearchReplace).last);
    // The replace runs real file IO; interleave frames with real event-loop
    // turns so the fake-async zone can complete the read/write.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();
    expect(find.text(l10n.workspaceSearchReplacedCount(1)), findsOneWidget);
    expect(File('${fixture.path}/a.dart').readAsStringSync(), 'hi world\n');
  });

  testWidgets(
    'results over the 2000 cap set the truncated flag',
    (tester) async {
      File('${fixture.path}/big.txt').writeAsStringSync(
        List.generate(2100, (i) => 'match line $i\n').join(),
      );
      final cubit = buildCubit();
      addTearDown(cubit.close);
      await tester.pumpWidget(wrap(cubit));
      await runSearch(tester, 'match');
      expect(cubit.state.truncated, isTrue);
    },
  );

  testWidgets('empty query clears results and shows the empty hint', (
    tester,
  ) async {
    final cubit = buildCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(wrap(cubit));
    await runSearch(tester, 'hello');
    expect(find.textContaining('hello world'), findsWidgets);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(cubit.state.files, isEmpty);
    expect(find.textContaining('hello world'), findsNothing);
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    expect(find.text(l10n.workspaceSearchEmptyHint), findsOneWidget);
  });

  testWidgets('summary row shows match and file counts after a search', (
    tester,
  ) async {
    final cubit = buildCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(wrap(cubit));
    await runSearch(tester, 'hello');
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    expect(find.text(l10n.workspaceSearchResultSummary(1, 1)), findsOneWidget);
  });

  testWidgets('tapping a file group header collapses and expands its lines', (
    tester,
  ) async {
    final cubit = buildCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(wrap(cubit));
    await runSearch(tester, 'hello');
    expect(find.textContaining('hello world'), findsWidgets);
    await tester.tap(find.textContaining('a.dart').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('hello world'), findsNothing);
    await tester.tap(find.textContaining('a.dart').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('hello world'), findsWidgets);
  });

  testWidgets('hover replace button replaces one file after confirm', (
    tester,
  ) async {
    final cubit = buildCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(wrap(cubit));
    await runSearch(tester, 'hello');
    await tester.enterText(find.byType(TextField).at(3), 'hi');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('search-file-replace-all')));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    expect(find.text(l10n.workspaceSearchReplaceAllTitle), findsOneWidget);
    await tester.tap(find.text(l10n.workspaceSearchReplace).last);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();
    expect(File('${fixture.path}/a.dart').readAsStringSync(), 'hi world\n');
  });
}
