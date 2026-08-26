import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/cubits/content_search/content_search_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/search/content_search_runner.dart';
import 'package:teampilot/services/search/content_replacer.dart';
import 'package:teampilot/widgets/right_tools/search_panel.dart';

/// Emits canned states so tests can pin exact render windows (the real
/// engine finishes inside one pump on small fixtures).
class _StubbedSearchCubit extends ContentSearchCubit {
  _StubbedSearchCubit()
    : super(
        runnerFactory: (_) => throw UnimplementedError(),
        replacerFactory: () => throw UnimplementedError(),
      );

  void debugEmitState(ContentSearchState state) => emit(state);
}

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
    await tester.tap(find.byTooltip(l10n.editorFindToggleReplace));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'hi');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('search-replace-all')));
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

  testWidgets('summary row shows the searching label while the engine runs', (
    tester,
  ) async {
    // The real engine drains within a single pump on this tiny fixture, so
    // drive the cubit states directly to pin the searching -> summary swap.
    final cubit = _StubbedSearchCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(wrap(cubit));
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    await tester.enterText(find.byType(TextField).first, 'hello');
    await tester.pump();
    expect(find.text(l10n.workspaceSearchSearching), findsNothing);

    cubit.debugEmitState(
      const ContentSearchState(query: 'hello', searching: true),
    );
    await tester.pump();
    expect(find.text(l10n.workspaceSearchSearching), findsOneWidget);

    cubit.debugEmitState(
      ContentSearchState(
        query: 'hello',
        files: [
          ContentSearchFileGroup(
            path: '${fixture.path}/a.dart',
            relativePath: 'a.dart',
            lines: [
              ContentSearchLineMatch(
                lineNumber: 1,
                lineText: 'hello world',
                matchStart: 0,
                matchEnd: 5,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pump();
    expect(find.text(l10n.workspaceSearchSearching), findsNothing);
    expect(find.text(l10n.workspaceSearchResultSummary(1, 1)), findsOneWidget);

    // Clearing the query re-arms the debounce so flushing it below runs the
    // safe empty branch instead of the stubbed engine.
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump(const Duration(milliseconds: 350));
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
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    await runSearch(tester, 'hello');
    await tester.tap(find.byTooltip(l10n.editorFindToggleReplace));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'hi');
    await tester.pump();

    // Without a prior hover the per-file action must stay inert: tapping it
    // must not open the confirm dialog.
    await tester.tap(find.byKey(const ValueKey('search-file-replace-all')));
    await tester.pump();
    expect(find.text(l10n.workspaceSearchReplaceAllTitle), findsNothing);

    // Synthesize mouse hover over the button to activate it.
    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer(
      location: tester.getCenter(
        find.byKey(const ValueKey('search-file-replace-all')),
      ),
    );
    addTearDown(hover.removePointer);
    await tester.pumpAndSettle();

    // The finder resolves through Tooltip's overlay surrogate, which never
    // participates in hit testing; the inner action receives the tap.
    await tester.tap(
      find.byKey(const ValueKey('search-file-replace-all')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
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

  testWidgets('chevron toggles the replace row', (tester) async {
    final cubit = buildCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(wrap(cubit));
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    expect(find.byKey(const ValueKey('search-replace-all')), findsNothing);
    await tester.tap(find.byTooltip(l10n.editorFindToggleReplace));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-replace-all')), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.editorFindToggleReplace));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-replace-all')), findsNothing);
  });

  testWidgets('details toggle reveals include/exclude and gitignore', (
    tester,
  ) async {
    final cubit = buildCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(wrap(cubit));
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text(l10n.workspaceSearchFilesToInclude), findsNothing);
    await tester.tap(find.byTooltip(l10n.workspaceSearchToggleDetails));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.text(l10n.workspaceSearchFilesToInclude), findsOneWidget);
    expect(find.text(l10n.workspaceSearchFilesToExclude), findsOneWidget);
    expect(find.text(l10n.workspaceSearchUseGitignore), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.workspaceSearchToggleDetails));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('option toggles flow into the searched options', (tester) async {
    final cubit = buildCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(wrap(cubit));
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    await tester.tap(find.byTooltip(l10n.workspaceSearchToggleDetails));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.editorFindMatchCase));
    await tester.tap(find.byTooltip(l10n.editorFindUseRegex));
    await tester.pump();
    await runSearch(tester, 'hello');
    expect(cubit.state.useGitignore, isFalse);
    expect(cubit.state.caseSensitive, isTrue);
    expect(cubit.state.isRegex, isFalse);
  });
}
