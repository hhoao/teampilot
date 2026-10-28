import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/usage/widgets/usage_trend_chart.dart';

Widget _wrap(Widget child, {double textScale = 1.0}) {
  return MaterialApp(
    locale: const Locale('zh'),
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

List<UsageChartDay> _days(int nowMs) => [
  for (var i = 6; i >= 0; i--)
    UsageChartDay(
      dayStartMs: nowMs - i * Duration.millisecondsPerDay,
      tokensByCli: {CliTool.claude: 1000 * (7 - i), CliTool.codex: 500},
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
      ),
    );

    expect(tester.takeException(), isNull);
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

    expect(tester.takeException(), isNull);
  });
}
