import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_graph_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/git_graph/git_graph_column_header.dart';
import 'package:teampilot/pages/git_graph/git_graph_pane.dart';

import '../../support/git_graph_test_fakes.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('toolbar and header menu toggle column header visibility', (
    tester,
  ) async {
    final graph = GitGraphCubit(
      history: FakeHistoryForGraph(rows: [graphCommitRow('abcdef123456')]),
      git: FakeGitForGraph(repoStatus()),
    );
    final layout = LayoutCubit();
    addTearDown(graph.close);
    addTearDown(layout.close);
    await graph.setRepoRoot('/repo');

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: graph),
          BlocProvider.value(value: layout),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(
            body: GitGraphPane(workspaceId: 'ws', repoRoot: '/repo'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GitGraphColumnHeader), findsOneWidget);

    await tester.tap(find.byIcon(Icons.view_column_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(GitGraphColumnHeader), findsNothing);

    await tester.tap(find.byIcon(Icons.view_column_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(GitGraphColumnHeader), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GitGraphColumnHeader)),
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide column header'));
    await tester.pumpAndSettle();

    expect(find.byType(GitGraphColumnHeader), findsNothing);
    expect(layout.state.preferences.gitGraphHeaderVisible, isFalse);
  });

  testWidgets('description header aligns with linear commit subject', (
    tester,
  ) async {
    final graph = GitGraphCubit(
      history: FakeHistoryForGraph(rows: [graphCommitRow('abcdef123456')]),
      git: FakeGitForGraph(repoStatus()),
    );
    final layout = LayoutCubit();
    addTearDown(graph.close);
    addTearDown(layout.close);
    await graph.setRepoRoot('/repo');

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: graph),
          BlocProvider.value(value: layout),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(
            body: GitGraphPane(workspaceId: 'ws', repoRoot: '/repo'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Description')).dx,
      closeTo(tester.getTopLeft(find.text('s-abcdef123456')).dx, 0.01),
    );
  });

  testWidgets('uncommitted commit slot aligns with commit hash column', (
    tester,
  ) async {
    final graph = GitGraphCubit(
      history: FakeHistoryForGraph(rows: [graphCommitRow('abcdef123456')]),
      git: FakeGitForGraph(dirtyStatus()),
    );
    final layout = LayoutCubit();
    addTearDown(graph.close);
    addTearDown(layout.close);
    await graph.setRepoRoot('/repo');

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: graph),
          BlocProvider.value(value: layout),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(
            body: GitGraphPane(workspaceId: 'ws', repoRoot: '/repo'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final uncommittedRow = find
        .ancestor(
          of: find.byIcon(Icons.edit_note_rounded),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.constraints?.maxHeight == 26,
          ),
        )
        .first;
    final commitSlot = find.descendant(
      of: uncommittedRow,
      matching: find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.width == 72,
      ),
    );

    expect(commitSlot, findsOneWidget);
    expect(
      tester.getTopLeft(commitSlot).dx,
      tester.getTopLeft(find.text('abcdef12')).dx,
    );
  });
}
