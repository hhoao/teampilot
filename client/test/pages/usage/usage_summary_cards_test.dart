import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
import 'package:teampilot/pages/usage/widgets/usage_summary_cards.dart';

final _dashboard = UsageDashboard(
  summary: const UsageSummary(
    totalTokens: 1234567,
    freshInputTokens: 456789,
    outputTokens: 234567,
    cacheReadTokens: 543211,
    cacheCreationTokens: 12345,
    requests: 321,
    sessions: 12,
    cacheHitRate: 0.5432,
  ),
  chart: [
    for (var i = 0; i < 7; i++)
      UsageChartDay(dayStartMs: i * 86400000, tokensByCli: const {}),
  ],
);

Widget _wrap({
  required double width,
  required double fontSizeFactor,
  Locale locale = const Locale('en'),
}) {
  final base = ThemeData(useMaterial3: true);
  final textTheme = base.textTheme;
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: base.copyWith(
      // Mirrors the app: typography is scaled through the theme type sizes.
      textTheme: textTheme.copyWith(
        titleLarge: textTheme.titleLarge?.copyWith(
          fontSize: 20 * fontSizeFactor,
        ),
        bodySmall: textTheme.bodySmall?.copyWith(fontSize: 12 * fontSizeFactor),
        labelSmall: textTheme.labelSmall?.copyWith(
          fontSize: 11 * fontSizeFactor,
        ),
      ),
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: UsageSummaryCards(
              dashboard: _dashboard,
              nowMs: DateTime.now().millisecondsSinceEpoch,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  // Typography is scaled through the theme (not MediaQuery.textScaler), so the
  // cards must grow with their content instead of a fixed height.
  for (final fontSizeFactor in <double>[1.0, 1.3, 1.6]) {
    for (final width in <double>[420, 700, 1200]) {
      testWidgets(
        'summary cards fit width=$width at font scale $fontSizeFactor',
        (tester) async {
          tester.view.physicalSize = const Size(1400, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            _wrap(width: width, fontSizeFactor: fontSizeFactor),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('Total tokens'), findsOneWidget);
        },
      );
    }
  }

  testWidgets('summary cards fit a long zh label', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(width: 700, fontSizeFactor: 1.3, locale: const Locale('zh')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('sparkline renders as a fl_chart bar chart', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap(width: 700, fontSizeFactor: 1.0));
    await tester.pumpAndSettle();

    expect(find.byType(BarChart), findsOneWidget);
    expect(tester.getSize(find.byType(UsageSparkline)).height, 26);
  });
}
