import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/usage/widgets/usage_cli_breakdown.dart';

const _summary = UsageSummary(
  totalTokens: 3000,
  freshInputTokens: 1000,
  outputTokens: 1000,
  cacheReadTokens: 1000,
  cacheCreationTokens: 0,
  requests: 10,
  sessions: 2,
  cacheHitRate: 0.33,
);

const _slices = <UsageCliSlice>[
  UsageCliSlice(
    cli: CliTool.claude,
    totalTokens: 2000,
    requests: 6,
    share: 2 / 3,
  ),
  UsageCliSlice(
    cli: CliTool.codex,
    totalTokens: 1000,
    requests: 4,
    share: 1 / 3,
  ),
];

Widget _wrap({
  List<UsageCliSlice> slices = _slices,
  CliTool? selectedCli,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        ColorScheme.fromSeed(seedColor: Colors.indigo),
        scale: 1,
      ),
      child: Scaffold(
        body: SizedBox(
          width: 300,
          child: UsageCliBreakdown(
            slices: slices,
            summary: _summary,
            selectedCli: selectedCli,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders a donut with the total in the centre', (tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(PieChart), findsOneWidget);
    expect(find.text('3.0K'), findsOneWidget);
    expect(find.text('Total tokens'), findsOneWidget);
    expect(find.text('Claude Code'), findsOneWidget);
    expect(find.text('Codex'), findsOneWidget);
  });

  testWidgets('empty slices keep the no-data state', (tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap(slices: const []));
    await tester.pumpAndSettle();

    expect(find.byType(PieChart), findsNothing);
    expect(find.text('No data'), findsOneWidget);
  });

  testWidgets('dims the rows of unselected CLIs', (tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap(selectedCli: CliTool.codex));
    await tester.pumpAndSettle();

    final claudeRow = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.text('Claude Code'),
            matching: find.byType(Opacity),
          )
          .first,
    );
    final codexRow = tester.widget<Opacity>(
      find
          .ancestor(of: find.text('Codex'), matching: find.byType(Opacity))
          .first,
    );
    expect(claudeRow.opacity, 0.42);
    expect(codexRow.opacity, 1);
  });

  testWidgets('hovering a section shows that CLI in the centre', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(PieChart));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: rect.center);
    addTearDown(gesture.removePointer);
    await tester.pump();
    // A small horizontal offset avoids the 2px section separator that
    // fl_chart cuts along the -90° seam at the top of the ring.
    await gesture.moveTo(
      rect.center + Offset(rect.width * 0.02, -rect.height * 0.36),
    );
    await tester.pump();

    final center = find.byKey(const ValueKey('usageCliBreakdownCenter'));
    expect(
      find.descendant(of: center, matching: find.text('Claude Code')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: center, matching: find.text('67%')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: center, matching: find.text('2.0K')),
      findsOneWidget,
    );
  });

  testWidgets('all-zero slices keep the no-data state', (tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        slices: const [
          UsageCliSlice(
            cli: CliTool.claude,
            totalTokens: 0,
            requests: 0,
            share: 0,
          ),
          UsageCliSlice(
            cli: CliTool.codex,
            totalTokens: 0,
            requests: 0,
            share: 0,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PieChart), findsNothing);
    expect(find.text('No data'), findsOneWidget);
  });
}
