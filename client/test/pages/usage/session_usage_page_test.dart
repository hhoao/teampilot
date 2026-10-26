import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/session_usage_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/usage/session_usage_page.dart';
import 'package:teampilot/services/usage/session_usage_sync_service.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

final _nowMs = DateTime.now().millisecondsSinceEpoch;

SessionUsageEvent _event({
  String id = 'r1',
  String sessionId = 's1',
  CliTool cli = CliTool.claude,
  int input = 10,
  int output = 2,
}) {
  return SessionUsageEvent(
    requestId: id,
    cli: cli,
    model: 'claude-sonnet-4',
    inputTokens: input,
    outputTokens: output,
    cacheReadTokens: 0,
    cacheCreationTokens: 0,
    inputSemantics: UsageInputSemantics.fresh,
    timestampMs: _nowMs,
    sessionId: sessionId,
  );
}

AppSession _session(String id, String display) => AppSession(
  sessionId: id,
  workspaceId: 'w1',
  display: display,
  createdAt: 1,
);

Widget _wrap(
  SessionUsageCubit cubit, {
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: brightness),
        scale: 1,
      ),
      child: BlocProvider.value(
        value: cubit,
        child: const Scaffold(body: SessionUsagePage(embedded: true)),
      ),
    ),
  );
}

void main() {
  testWidgets('renders summary, chart, and grouped rows', (tester) async {
    final cubit = SessionUsageCubit(
      loadEvents: () async => [
        _event(),
        _event(id: 'r2', sessionId: 's2', cli: CliTool.codex, input: 20),
      ],
      syncAll: () async => const UsageSyncResult(),
      loadSessions: () async => [
        _session('s1', 'Alpha'),
        _session('s2', 'Beta'),
      ],
      loadTeams: () async => const <TeamProfile>[],
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.sessionUsagePage), findsOneWidget);
    expect(find.text('Token usage'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Claude Code'), findsWidgets);
    expect(find.byKey(AppKeys.sessionUsageEmptyState), findsNothing);
  });

  testWidgets('empty state syncs and reveals new usage', (tester) async {
    var events = <SessionUsageEvent>[];
    var syncCalls = 0;
    final cubit = SessionUsageCubit(
      loadEvents: () async => events,
      syncAll: () async {
        syncCalls++;
        events = [_event()];
        return const UsageSyncResult(inserted: 1);
      },
      loadSessions: () async => [_session('s1', 'Alpha')],
      loadTeams: () async => const <TeamProfile>[],
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.sessionUsageEmptyState), findsOneWidget);
    await tester.tap(find.byKey(AppKeys.sessionUsageSyncButton));
    await tester.pumpAndSettle();

    expect(syncCalls, 1);
    expect(find.byKey(AppKeys.sessionUsageEmptyState), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);

    // Let the success toast expire so the test leaves no pending timer.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('partial sync failure shows a dismissible banner', (
    tester,
  ) async {
    final cubit = SessionUsageCubit(
      loadEvents: () async => [_event()],
      syncAll: () async => const UsageSyncResult(
        errors: [UsageSyncError(sourceId: 'src', message: 'bad')],
      ),
      loadSessions: () async => [_session('s1', 'Alpha')],
      loadTeams: () async => const <TeamProfile>[],
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.sessionUsageSyncButton));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.sessionUsageErrorBanner), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.sessionUsageErrorBanner), findsNothing);
  });

  testWidgets('search filters table rows without hiding summary', (
    tester,
  ) async {
    final cubit = SessionUsageCubit(
      loadEvents: () async => [
        _event(),
        _event(id: 'r2', sessionId: 's2', cli: CliTool.codex, input: 20),
      ],
      syncAll: () async => const UsageSyncResult(),
      loadSessions: () async => [
        _session('s1', 'Alpha'),
        _session('s2', 'Beta'),
      ],
      loadTeams: () async => const <TeamProfile>[],
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    await tester.enterText(find.byKey(AppKeys.sessionUsageSearchField), 'Beta');
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Beta'), findsWidgets);
    expect(cubit.state.dashboard.rows.single.label, 'Beta');
    expect(find.text('Total tokens'), findsOneWidget);
  });

  testWidgets('load failure shows retry state', (tester) async {
    final cubit = SessionUsageCubit(
      loadEvents: () async => throw StateError('offline'),
      syncAll: () async => const UsageSyncResult(),
      loadSessions: () async => const <AppSession>[],
      loadTeams: () async => const <TeamProfile>[],
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    expect(find.text('Could not load usage data.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('renders in dark mode without overflow', (tester) async {
    final cubit = SessionUsageCubit(
      loadEvents: () async => [_event()],
      syncAll: () async => const UsageSyncResult(),
      loadSessions: () async => [_session('s1', 'Alpha')],
      loadTeams: () async => const <TeamProfile>[],
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit, brightness: Brightness.dark));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.sessionUsagePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('range, CLI, and group chips update the cubit', (tester) async {
    final cubit = SessionUsageCubit(
      loadEvents: () async => [
        _event(),
        _event(id: 'r2', sessionId: 's2', cli: CliTool.codex, input: 20),
      ],
      syncAll: () async => const UsageSyncResult(),
      loadSessions: () async => [
        _session('s1', 'Alpha'),
        _session('s2', 'Beta'),
      ],
      loadTeams: () async => const <TeamProfile>[],
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Last 7 days'));
    await tester.pumpAndSettle();
    expect(cubit.state.range, UsageRange.sevenDays);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Codex'));
    await tester.pumpAndSettle();
    expect(cubit.state.cli, CliTool.codex);
    expect(find.text('Alpha'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Model'));
    await tester.pumpAndSettle();
    expect(cubit.state.groupBy, UsageGroupBy.model);
  });

  testWidgets('sync button is disabled while syncing', (tester) async {
    final syncCompleter = Completer<UsageSyncResult>();
    final cubit = SessionUsageCubit(
      loadEvents: () async => [_event()],
      syncAll: () => syncCompleter.future,
      loadSessions: () async => [_session('s1', 'Alpha')],
      loadTeams: () async => const <TeamProfile>[],
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppKeys.sessionUsageSyncButton));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(AppKeys.sessionUsageSyncButton))
          .onPressed,
      isNull,
    );

    syncCompleter.complete(
      const UsageSyncResult(
        errors: [UsageSyncError(sourceId: 'src', message: 'bad')],
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(AppKeys.sessionUsageSyncButton))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('load reads cache once and never scans on open', (tester) async {
    var loadCount = 0;
    var syncCount = 0;
    final cubit = SessionUsageCubit(
      loadEvents: () async {
        loadCount++;
        return [_event()];
      },
      syncAll: () async {
        syncCount++;
        return const UsageSyncResult();
      },
      loadSessions: () async => [_session('s1', 'Alpha')],
      loadTeams: () async => const <TeamProfile>[],
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    expect(loadCount, 1);
    expect(syncCount, 0);
  });

  testWidgets('wide layout renders chart row without overflow', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = SessionUsageCubit(
      loadEvents: () async => [
        _event(),
        _event(id: 'r2', sessionId: 's2', cli: CliTool.codex, input: 20),
      ],
      syncAll: () async => const UsageSyncResult(),
      loadSessions: () async => [
        _session('s1', 'Alpha'),
        _session('s2', 'Beta'),
      ],
      loadTeams: () async => const <TeamProfile>[],
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.sessionUsagePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow layout keeps the table scrollable', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = SessionUsageCubit(
      loadEvents: () async => [_event()],
      syncAll: () async => const UsageSyncResult(),
      loadSessions: () async => [_session('s1', 'Alpha')],
      loadTeams: () async => const <TeamProfile>[],
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.sessionUsageTable), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
