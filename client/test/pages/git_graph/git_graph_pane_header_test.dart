import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/git_graph_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/git_graph.dart';
import 'package:teampilot/pages/git_graph/git_graph_column_header.dart';
import 'package:teampilot/pages/git_graph/git_graph_columns.dart';
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

    // 工具栏列菜单：点开 → 切换「列头」勾选项。
    await tester.tap(find.byIcon(Icons.view_column_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Column header'));
    await tester.pumpAndSettle();
    expect(find.byType(GitGraphColumnHeader), findsNothing);

    await tester.tap(find.byIcon(Icons.view_column_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Column header'));
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

  testWidgets('description aligns across rows with different lane depth', (
    tester,
  ) async {
    // 回归：图区宽度曾按每行各自 maxSlot 计算，深 lane 行的描述列起点
    // 更靠右，列不对齐。统一为全局最大 slot 后所有行 / 列头共用同一图宽。
    GitCommitRow rowAtSlot(int slot, String hash) => GitCommitRow(
      edges: [GitGraphEdge(slot, slot, 0)],
      node: GitGraphNode(slot, 0),
      hash: hash,
      parents: const ['p'],
      authorName: 'Ann',
      authorEmail: 'ann@x',
      authorDate: DateTime.utc(2026, 8, 25, 10, 30),
      subject: 's-$hash',
      refs: const [],
    );

    final graph = GitGraphCubit(
      history: FakeHistoryForGraph(
        rows: [rowAtSlot(0, 'shallow'), rowAtSlot(6, 'deep')],
      ),
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

    final shallowDx = tester.getTopLeft(find.text('s-shallow')).dx;
    final deepDx = tester.getTopLeft(find.text('s-deep')).dx;
    final headerDx = tester.getTopLeft(find.text('Description')).dx;
    expect(shallowDx, closeTo(deepDx, 0.01));
    expect(headerDx, closeTo(deepDx, 0.01));
  });

  testWidgets('toolbar column menu hides and restores the date column', (
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

    Future<void> pumpHost() async {
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
    }

    await pumpHost();
    // graphCommitRow 的 authorDate 是 epoch；按「MM/dd」格式断言（时区无关）。
    Finder dateValue() => find.textContaining(RegExp(r'^\d{2}/\d{2} '));
    expect(dateValue(), findsOneWidget); // 提交行日期
    expect(find.text('Date'), findsOneWidget); // 列头日期

    await tester.tap(find.byIcon(Icons.view_column_outlined));
    await tester.pumpAndSettle();
    final menuDate = find.descendant(
      of: find.byType(TpActionMenuItem),
      matching: find.text('Date'),
    );
    expect(menuDate, findsOneWidget);
    await tester.tap(menuDate);
    await tester.pumpAndSettle();

    expect(dateValue(), findsNothing);
    expect(find.text('Date'), findsNothing);
    expect(
      layout.state.preferences.gitGraphColumns.hiddenColumns,
      contains(GitGraphColumnId.date),
    );
    expect(find.text('Author'), findsOneWidget); // 其它列不受影响

    // 恢复：菜单再次勾选 Date。
    await tester.tap(find.byIcon(Icons.view_column_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();
    expect(dateValue(), findsOneWidget);
  });

  testWidgets('meta column labels align with row values on both edges', (
    tester,
  ) async {
    // 回归：行内日期 / 作者列曾是 Flexible(flex)，与列头的固定宽列边界
    // 对不上（800px 宽下列头 100px、行内 ~94px），且行单元格带 4px 内边距
    // 而列头没有。共享列骨架后两侧边缘必须逐像素一致。
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

    // 列头标签 vs 行内值的左缘（列头单元格 key 由列头提供）。
    void expectAligned(Finder headerCell, Finder rowValue, String what) {
      final headerLeft = tester.getTopLeft(headerCell).dx;
      final valueLeft = tester.getTopLeft(rowValue).dx;
      final headerRight = tester.getTopRight(headerCell).dx;
      final valueRight = tester.getTopRight(rowValue).dx;
      expect(valueLeft, closeTo(headerLeft, 0.01), reason: '$what 左缘未对齐');
      expect(valueRight, closeTo(headerRight, 0.01), reason: '$what 右缘未对齐');
    }

    expectAligned(
      find.byKey(const ValueKey('git-graph-header-cell-date')),
      find.textContaining(RegExp(r'^\d{2}/\d{2} ')),
      '日期列',
    );
    expectAligned(
      find.byKey(const ValueKey('git-graph-header-cell-author')),
      find.text('A'),
      '作者列',
    );
    expectAligned(
      find.byKey(const ValueKey('git-graph-header-cell-commit')),
      find.text('abcdef12'),
      '提交列',
    );
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
                widget is Container &&
                widget.padding ==
                    const EdgeInsets.symmetric(
                      horizontal: GitGraphColumns.horizontalPadding,
                      vertical: GitGraphColumns.rowVerticalPadding,
                    ),
          ),
        )
        .first;
    final commitSlot = find.descendant(
      of: uncommittedRow,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is SizedBox && widget.width == GitGraphColumns.commitWidth,
      ),
    );

    expect(commitSlot, findsOneWidget);
    expect(
      tester.getTopLeft(commitSlot).dx,
      tester.getTopLeft(find.text('abcdef12')).dx,
    );
  });
}
