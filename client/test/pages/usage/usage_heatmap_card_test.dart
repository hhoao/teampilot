import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
import 'package:teampilot/pages/usage/widgets/usage_heatmap_card.dart';

final _now = DateTime(2026, 10, 28, 12).millisecondsSinceEpoch;
final _today = DateTime(2026, 10, 28);

UsageHeatmapDay _day(
  DateTime date, {
  int tokens = 100,
  int requests = 1,
  int costMicroUsd = 0,
  double? hitRate,
}) {
  return UsageHeatmapDay(
    dayStartMs: DateTime(date.year, date.month, date.day).millisecondsSinceEpoch,
    tokens: tokens,
    requests: requests,
    costMicroUsd: costMicroUsd,
    cacheHitRate: hitRate,
  );
}

Widget _wrap(Widget child, {double width = 1000}) {
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
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );
}

Finder _cells() => find.byWidgetPredicate(
  (widget) =>
      widget is Container &&
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('usageHeatmapCell-'),
);

Color? _cellColor(WidgetTester tester, DateTime date) {
  final container = tester.widget<Container>(
    find.byKey(ValueKey('usageHeatmapCell-${date.millisecondsSinceEpoch}')),
  );
  return (container.decoration! as BoxDecoration).color;
}

void main() {
  testWidgets('renders one 53x7 grid for the current span', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        UsageHeatmapCard(
          days: [
            _day(
              _today,
              tokens: 1000,
              requests: 5,
              costMicroUsd: 1000000,
              hitRate: 0.5,
            ),
          ],
          nowMs: _now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Usage heatmap'), findsOneWidget);
    expect(_cells(), findsNWidgets(371));
    expect(find.text('Show earlier'), findsNothing);
  });

  testWidgets('tooltip lists tokens, requests, cost and hit rate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        UsageHeatmapCard(
          days: [
            _day(
              _today,
              tokens: 1000,
              requests: 5,
              costMicroUsd: 1000000,
              hitRate: 0.5,
            ),
          ],
          nowMs: _now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tooltip = tester.widget<Tooltip>(
      find
          .ancestor(
            of: find.byKey(
              ValueKey('usageHeatmapCell-${_today.millisecondsSinceEpoch}'),
            ),
            matching: find.byType(Tooltip),
          )
          .first,
    );
    expect(tooltip.message, contains('Total tokens 1.0K'));
    expect(tooltip.message, contains('Requests 5'));
    expect(tooltip.message, contains(r'Cost $1.00'));
    expect(tooltip.message, contains('Hit rate 50%'));
  });

  testWidgets('metric switch re-colours cells', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        UsageHeatmapCard(
          days: [
            _day(_today, tokens: 1000, requests: 1),
            _day(DateTime(2026, 10, 27), tokens: 10, requests: 100),
          ],
          nowMs: _now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tokenColor = _cellColor(tester, _today);
    await tester.tap(find.text('Requests'));
    await tester.pumpAndSettle();
    final requestColor = _cellColor(tester, _today);

    expect(requestColor, isNot(tokenColor));
  });

  testWidgets('show earlier reveals the older span', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        UsageHeatmapCard(
          days: [_day(DateTime(2025, 10, 20), tokens: 5)],
          nowMs: _now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_cells(), findsNWidgets(371));
    await tester.tap(find.text('Show earlier'));
    await tester.pumpAndSettle();
    expect(_cells(), findsNWidgets(742));
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('empty days keep the no-data state', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(const UsageHeatmapCard(days: [], nowMs: 0)),
    );
    await tester.pumpAndSettle();

    expect(_cells(), findsNothing);
    expect(find.text('No data'), findsOneWidget);
    expect(find.text('Less'), findsNothing);
    expect(find.text('More'), findsNothing);
  });

  testWidgets('fits a narrow card without overflowing', (tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        UsageHeatmapCard(days: [_day(_today)], nowMs: _now),
        width: 400,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_cells(), findsNWidgets(371));
  });
}
