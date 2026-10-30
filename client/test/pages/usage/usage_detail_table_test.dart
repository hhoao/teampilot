import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/usage/widgets/usage_detail_table.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/services/usage/usage_aggregator.dart';

UsageDashboard _dashboard() {
  final now = DateTime(2026, 10, 26, 12).millisecondsSinceEpoch;
  final events = [
    SessionUsageEvent(
      requestId: 'r1',
      cli: CliTool.claude,
      model: 'sonnet',
      inputTokens: 10,
      outputTokens: 2,
      cacheReadTokens: 0,
      cacheCreationTokens: 0,
      inputSemantics: UsageInputSemantics.fresh,
      timestampMs: now,
      sessionId: 's1',
    ),
    SessionUsageEvent(
      requestId: 'r2',
      cli: CliTool.codex,
      model: 'gpt',
      inputTokens: 100,
      outputTokens: 20,
      cacheReadTokens: 0,
      cacheCreationTokens: 0,
      inputSemantics: UsageInputSemantics.fresh,
      timestampMs: now,
      sessionId: 's2',
    ),
  ];
  return buildUsageDashboard(
    events: events,
    attribution: const UsageAttribution(
      sessionTitles: {'s1': 'Alpha', 's2': 'Beta'},
    ),
    filter: const UsageFilter(),
    nowMs: now,
  );
}

Widget _wrap({
  required UsageDashboard dashboard,
  required AppSettingsRepository repository,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: RepositoryProvider<AppSettingsRepository>.value(
      value: repository,
      child: TpTheme(
        data: TpThemeData.fromColorScheme(
          ColorScheme.fromSeed(seedColor: Colors.indigo),
          scale: 1,
        ),
        child: Scaffold(
          body: UsageDetailTable(
            dashboard: dashboard,
            groupBy: UsageGroupBy.session,
            searchController: TextEditingController(),
            onQueryChanged: (_) {},
            onGroupByChanged: (_) {},
            onResetFilters: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders group controls in the table card', (tester) async {
    tester.view.physicalSize = const Size(1300, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        dashboard: _dashboard(),
        repository: InMemoryAppSettingsRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Sessions'), findsNothing);
    expect(find.textContaining('Group by'), findsOneWidget);
  });

  testWidgets('hiding a column persists and removes its header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = InMemoryAppSettingsRepository();
    await tester.pumpWidget(
      _wrap(dashboard: _dashboard(), repository: repository),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(TpTableHeader<UsageGroup>),
        matching: find.text('Share'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.view_column_outlined));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(TpActionMenuPanel),
        matching: find.text('Share'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(TpTableHeader<UsageGroup>),
        matching: find.text('Share'),
      ),
      findsNothing,
    );
    final saved = await repository.loadTableState('usage.detail');
    expect(saved?['hidden'], contains('share'));
  });

  testWidgets('clicking the total header reverses row order', (tester) async {
    tester.view.physicalSize = const Size(1300, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        dashboard: _dashboard(),
        repository: InMemoryAppSettingsRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Beta')).dy,
      lessThan(tester.getTopLeft(find.text('Alpha')).dy),
    );

    await tester.tap(find.text('Total'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Beta')).dy),
    );
  });
}
