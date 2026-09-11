import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/pages/git_graph/git_graph_column_header.dart';
import 'package:teampilot/pages/git_graph/git_graph_column_layout.dart';

typedef HostBundle = ({Widget host, LayoutCubit cubit});

/// 偏好初始值需 pump 后经 [LayoutCubit.setGitGraphColumns] 注入
/// （cubit 初始 state 固定为默认偏好），见 [pumpHost]。
HostBundle _host() {
  final controller = GitGraphColumnLayoutController(maxSlot: 2);
  final cubit = LayoutCubit();
  return (
    host: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: BlocProvider.value(
        value: cubit,
        child: Builder(
          builder: (context) {
            // 复刻 _PaneBody 的接线：偏好变化静默同步回控制器。
            context.select<LayoutCubit, GitGraphColumnPrefs>(
              (c) => c.state.preferences.gitGraphColumns,
            );
            controller.sync(cubit.state.preferences.gitGraphColumns);
            return Scaffold(body: GitGraphColumnHeader(controller: controller));
          },
        ),
      ),
    ),
    cubit: cubit,
  );
}

Future<void> pumpHost(
  WidgetTester tester, {
  GitGraphColumnPrefs prefs = const GitGraphColumnPrefs(),
}) async {
  final bundle = _host();
  addTearDown(bundle.cubit.close);
  await tester.pumpWidget(bundle.host);
  await bundle.cubit.setGitGraphColumns(prefs);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders five column labels by default', (tester) async {
    await pumpHost(tester);

    expect(find.text('Graph'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Author'), findsOneWidget);
    expect(find.text('Commit'), findsOneWidget);
  });

  testWidgets('hidden column omits its label and resize handle', (
    tester,
  ) async {
    await pumpHost(
      tester,
      prefs: const GitGraphColumnPrefs(
        hiddenColumns: {GitGraphColumnId.date},
      ),
    );

    expect(find.text('Date'), findsNothing);
    expect(find.text('Author'), findsOneWidget);
  });

  testWidgets('secondary tap on a column hides that column', (tester) async {
    await pumpHost(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Date')),
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hide Date'));
    await tester.pumpAndSettle();

    expect(find.text('Date'), findsNothing);
  });

  testWidgets('secondary tap on description offers only header hiding', (
    tester,
  ) async {
    await pumpHost(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Description')),
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Hide Date'), findsNothing);
    expect(find.text('Hide column header'), findsOneWidget);

    await tester.tap(find.text('Hide column header'));
    await tester.pumpAndSettle();
  });

  testWidgets('dragging a resize handle follows the cursor direction', (
    tester,
  ) async {
    await pumpHost(tester);

    Finder dateCell() =>
        find.byKey(const ValueKey('git-graph-header-cell-date'));
    Finder firstHandle() => find
        .byWidgetPredicate(
          (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
        )
        .first;
    final before = tester.getSize(dateCell()).width;
    final handleDxBefore = tester.getTopLeft(firstHandle()).dx;

    // 首条分隔条（描述|日期）：向左拖 60 → 日期列变宽、分隔条跟随左移
    // （回归：旧实现拖右 60 时分隔条反向左跳 60）。
    await tester.drag(firstHandle(), const Offset(-60, 0));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(dateCell()).width, greaterThan(before));
    expect(
      tester.getTopLeft(firstHandle()).dx,
      lessThan(handleDxBefore),
      reason: '分隔条必须跟随光标方向移动',
    );
  });

  testWidgets('trailing edge handle widens the commit column', (
    tester,
  ) async {
    await pumpHost(tester);

    Finder commitCell() =>
        find.byKey(const ValueKey('git-graph-header-cell-commit'));
    Finder lastHandle() => find
        .byWidgetPredicate(
          (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
        )
        .last;
    final before = tester.getSize(commitCell()).width;

    await tester.drag(lastHandle(), const Offset(40, 0));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(commitCell()).width, greaterThan(before));
  });
}
