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
  ValueChanged<UsageGroupBy>? onGroupByChanged,
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  bool isComputing = false,
}) {
  return MaterialApp(
    locale: locale,
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
          body: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: UsageDetailTable(
                dashboard: dashboard,
                groupBy: UsageGroupBy.session,
                searchController: TextEditingController(),
                onQueryChanged: (_) {},
                onGroupByChanged: onGroupByChanged ?? (_) {},
                onResetFilters: () {},
                isComputing: isComputing,
              ),
            ),
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
    final segment = tester.widget<TpSegmentedControl>(
      find.byType(TpSegmentedControl),
    );
    expect(segment.labels, ['Session', 'Member', 'Model', 'CLI']);
    expect(find.textContaining('Group by'), findsNothing);
  });

  testWidgets('shows a loading overlay while computing', (tester) async {
    await tester.pumpWidget(
      _wrap(
        dashboard: _dashboard(),
        repository: InMemoryAppSettingsRepository(),
        isComputing: true,
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('rows fit at 1.3x text scale', (tester) async {
    tester.view.physicalSize = const Size(1300, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        dashboard: _dashboard(),
        repository: InMemoryAppSettingsRepository(),
        textScaler: const TextScaler.linear(1.3),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('resizing a column persists its width', (tester) async {
    tester.view.physicalSize = const Size(1300, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = InMemoryAppSettingsRepository();
    await tester.pumpWidget(
      _wrap(dashboard: _dashboard(), repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('resize-total')),
      const Offset(30, 0),
    );
    await tester.pumpAndSettle();

    final saved = await repository.loadTableState('usage.detail');
    expect(saved?['widths'], isA<Map<String, dynamic>>());
    expect((saved?['widths'] as Map)['total'], greaterThan(100));
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

  testWidgets('group segment reports the selection', (tester) async {
    tester.view.physicalSize = const Size(1300, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    UsageGroupBy? selected;
    await tester.pumpWidget(
      _wrap(
        dashboard: _dashboard(),
        repository: InMemoryAppSettingsRepository(),
        onGroupByChanged: (group) => selected = group,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(TpSegmentedControl),
        matching: find.text('Model'),
      ),
    );
    await tester.pumpAndSettle();

    expect(selected, UsageGroupBy.model);
  });

  testWidgets('empty-state headline uses the medium body token', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        dashboard: const UsageDashboard(),
        repository: InMemoryAppSettingsRepository(),
      ),
    );
    await tester.pumpAndSettle();

    final headlineFinder = find.text('No matching rows');
    final headline = tester.widget<Text>(headlineFinder);
    expect(
      headline.style,
      TpTextStyles.of(tester.element(headlineFinder)).smMedium,
    );
  });

  testWidgets('sort tooltip uses localized table labels', (tester) async {
    tester.view.physicalSize = const Size(1300, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        dashboard: _dashboard(),
        repository: InMemoryAppSettingsRepository(),
        locale: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('升序'), findsOneWidget);
  });

  testWidgets('clicking the total header reverses row order', (tester) async {
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
      tester.getTopLeft(find.text('Beta')).dy,
      lessThan(tester.getTopLeft(find.text('Alpha')).dy),
    );

    await tester.tap(find.text('Total'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Beta')).dy),
    );
    expect(find.text('Total'), findsOneWidget);
    expect(
      (await repository.loadTableState('usage.detail'))?.containsKey('sort'),
      isFalse,
    );
  });
}
