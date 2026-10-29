import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/usage/widgets/usage_trend_chart.dart';

Widget _wrap(
  Widget child, {
  double textScale = 1.0,
  Locale locale = const Locale('zh'),
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, appChild) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: appChild!,
    ),
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        ColorScheme.fromSeed(seedColor: Colors.indigo),
        scale: 1,
      ),
      child: Scaffold(body: child),
    ),
  );
}

List<UsageChartDay> _days(int nowMs, {int count = 7}) => [
  for (var i = count - 1; i >= 0; i--)
    UsageChartDay(
      dayStartMs: nowMs - i * Duration.millisecondsPerDay,
      tokensByCli: {CliTool.claude: 1000 * (i + 1), CliTool.codex: 500},
    ),
];

void main() {
  testWidgets('fits the tallest day inside the chart box', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final nowMs = DateTime(2026, 10, 28, 12).millisecondsSinceEpoch;
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 1000,
          child: UsageTrendChart(days: _days(nowMs), nowMs: nowMs),
        ),
        // English so the tooltip total line reads "{tokens} total".
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BarChart), findsOneWidget);

    final chart = tester.widget<BarChart>(find.byType(BarChart));
    final groups = chart.data.barGroups;
    final tip = chart.data.barTouchData.touchTooltipData.getTooltipItem(
      groups[3],
      3,
      groups[3].barRods.single,
      0,
    )!;
    expect(tip.text, '10/25');
    final spanTexts = [
      for (final child in tip.children ?? const <InlineSpan>[])
        if (child is TextSpan) child.text ?? '',
    ];
    expect(spanTexts, contains('\nClaude Code · 4.0K'));
    expect(spanTexts, contains('\nCodex · 500'));
    expect(
      spanTexts.where((text) => text.contains('4.5K total')),
      hasLength(1),
    );
  });

  testWidgets('fits when day labels are taller than the reserved slot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final nowMs = DateTime(2026, 10, 28, 12).millisecondsSinceEpoch;
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 1000,
          child: UsageTrendChart(days: _days(nowMs), nowMs: nowMs),
        ),
        textScale: 1.4,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the empty state instead of a chart for all-zero days', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final nowMs = DateTime(2026, 10, 28, 12).millisecondsSinceEpoch;
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 1000,
          child: UsageTrendChart(
            days: [UsageChartDay(dayStartMs: nowMs)],
            nowMs: nowMs,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BarChart), findsNothing);
    expect(find.text('暂无数据'), findsOneWidget);
  });

  testWidgets('lays out a thirty-day range', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final nowMs = DateTime(2026, 10, 28, 12).millisecondsSinceEpoch;
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 1100,
          child: UsageTrendChart(days: _days(nowMs, count: 30), nowMs: nowMs),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BarChart), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
    final dayLabels = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.data != null &&
          RegExp(r'^\d{1,2}/\d{1,2}$').hasMatch(widget.data!),
    );
    // 30 days at stride 5: the axis renders at most six date labels.
    expect(dayLabels.evaluate().length, lessThanOrEqualTo(6));
  });
}
