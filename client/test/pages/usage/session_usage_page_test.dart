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
import 'package:teampilot/pages/usage/widgets/usage_heatmap_card.dart';
import 'package:teampilot/services/usage/session_usage_sync_service.dart';
import 'package:teampilot/services/usage/usage_sync_control.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

final _nowMs = DateTime.now().millisecondsSinceEpoch;

SessionUsageEvent _event({
  String id = 'r1',
  String sessionId = 's1',
  CliTool cli = CliTool.claude,
  String model = 'claude-sonnet-4',
  int input = 10,
  int output = 2,
}) {
  return SessionUsageEvent(
    requestId: id,
    cli: cli,
    model: model,
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

List<SessionUsageEvent> _pagedEvents(int count) => [
  for (var i = 1; i <= count; i++)
    _event(id: 'r$i', sessionId: 's$i', input: 200 - i),
];

List<AppSession> _pagedSessions(int count) => [
  for (var i = 1; i <= count; i++) _session('s$i', 'Session $i'),
];

SessionUsageCubit _pagedCubit(int count) => SessionUsageCubit(
  loadEvents: () async => _pagedEvents(count),
  syncAll: () async => const UsageSyncResult(),
  loadSessions: () async => _pagedSessions(count),
  loadTeams: () async => const <TeamProfile>[],
);

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _chooseSync(
  WidgetTester tester, {
  required Key item,
  bool settle = true,
}) async {
  await tester.tap(find.byKey(AppKeys.sessionUsageSyncButton));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(item));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Widget _wrap(
  SessionUsageCubit cubit, {
  Brightness brightness = Brightness.light,
  bool autoSync = false,
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
        child: Scaffold(
          body: SessionUsagePage(embedded: true, autoSync: autoSync),
        ),
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
    await _chooseSync(tester, item: AppKeys.sessionUsageIncrementalSync);

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
    await _chooseSync(tester, item: AppKeys.sessionUsageIncrementalSync);

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
    // Only the range-filtered summary card is labelled "Total tokens"; the
    // breakdown donut centre is scoped to the last seven days.
    expect(find.text('Total tokens'), findsOneWidget);
    expect(find.byType(UsageHeatmapCard), findsOneWidget);
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

  testWidgets('sync shows progress and cancels the active handle', (
    tester,
  ) async {
    final progress = StreamController<UsageSyncProgress>(sync: true);
    final done = Completer<UsageSyncResult>();
    var cancelCalls = 0;
    final handle = UsageSyncHandle(
      done: done.future,
      progress: progress.stream,
      cancel: () => cancelCalls++,
    );
    final cubit = SessionUsageCubit(
      loadEvents: () async => [_event()],
      syncAll: () async => const UsageSyncResult(),
      startSync: () => handle,
      loadSessions: () async => [_session('s1', 'Alpha')],
      loadTeams: () async => const <TeamProfile>[],
    );
    addTearDown(() async {
      await progress.close();
      await cubit.close();
    });

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppKeys.sessionUsageSyncButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.sessionUsageIncrementalSync));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.sessionUsageCancelSyncButton), findsOneWidget);

    progress.add(
      const UsageSyncProgress(targetsTotal: 2, targetsDone: 1, inserted: 3),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.sessionUsageSyncProgress), findsOneWidget);
    expect(find.textContaining('Scanning 1/2'), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.sessionUsageCancelSyncButton));
    expect(cancelCalls, 1);
    expect(cubit.state.isCancelling, isTrue);

    done.complete(const UsageSyncResult(cancelled: true));
    await tester.pumpAndSettle();
    expect(cubit.state.syncCancelled, isTrue);
    expect(find.byKey(AppKeys.sessionUsageSyncButton), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('full sync menu option starts a full scan', (tester) async {
    final done = Completer<UsageSyncResult>();
    var fullCalls = 0;
    final handle = UsageSyncHandle(
      done: done.future,
      progress: const Stream<UsageSyncProgress>.empty(),
      cancel: () {},
    );
    final cubit = SessionUsageCubit(
      loadEvents: () async => [_event()],
      syncAll: () async => const UsageSyncResult(),
      startFullSync: () {
        fullCalls++;
        return handle;
      },
      loadSessions: () async => [_session('s1', 'Alpha')],
      loadTeams: () async => const <TeamProfile>[],
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppKeys.sessionUsageSyncButton));
    await tester.pumpAndSettle();
    expect(find.text('Incremental sync'), findsOneWidget);
    expect(find.text('Full sync'), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.sessionUsageFullSync));
    await tester.pumpAndSettle();
    expect(fullCalls, 1);
    expect(find.byKey(AppKeys.sessionUsageCancelSyncButton), findsOneWidget);

    done.complete(const UsageSyncResult(inserted: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.sessionUsageSyncButton), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('header hosts cursor and storage actions without footer notes', (
    tester,
  ) async {
    final cubit = _pagedCubit(2);
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.sessionUsageCursorButton), findsOneWidget);
    expect(find.byKey(AppKeys.sessionUsageMaintenanceButton), findsOneWidget);
    expect(find.text('JSONL read-only'), findsNothing);
    expect(find.text('Auto + manual sync'), findsNothing);
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

  testWidgets('auto sync scans once on open when stale', (tester) async {
    var syncCount = 0;
    final cubit = SessionUsageCubit(
      loadEvents: () async => [_event()],
      syncAll: () async {
        syncCount++;
        return const UsageSyncResult();
      },
      loadSessions: () async => [_session('s1', 'Alpha')],
      loadTeams: () async => const <TeamProfile>[],
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit, autoSync: true));
    await tester.pumpAndSettle();

    expect(syncCount, 1);
  });

  testWidgets('auto sync timer rechecks stale data while visible', (
    tester,
  ) async {
    var now = DateTime(2026, 10, 26, 18);
    var syncCount = 0;
    final cubit = SessionUsageCubit(
      loadEvents: () async => [_event()],
      syncAll: () async {
        syncCount++;
        return const UsageSyncResult();
      },
      loadSessions: () async => [_session('s1', 'Alpha')],
      loadTeams: () async => const <TeamProfile>[],
      now: () => now,
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit, autoSync: true));
    await tester.pumpAndSettle();
    expect(syncCount, 1);

    now = now.add(const Duration(minutes: 11));
    await tester.pump(const Duration(minutes: 10));
    await tester.pumpAndSettle();
    expect(syncCount, 2);
  });

  testWidgets('auto sync rechecks stale data on app resume', (tester) async {
    var now = DateTime(2026, 10, 26, 18);
    var syncCount = 0;
    final cubit = SessionUsageCubit(
      loadEvents: () async => [_event()],
      syncAll: () async {
        syncCount++;
        return const UsageSyncResult();
      },
      loadSessions: () async => [_session('s1', 'Alpha')],
      loadTeams: () async => const <TeamProfile>[],
      now: () => now,
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit, autoSync: true));
    await tester.pumpAndSettle();
    expect(syncCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    now = now.add(const Duration(minutes: 11));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(syncCount, 2);
  });

  testWidgets('shows cost and unpriced rows', (tester) async {
    final cubit = SessionUsageCubit(
      loadEvents: () async => [
        _event(
          id: 'priced',
          sessionId: 's1',
          model: 'claude-sonnet-4-5',
          input: 1000000,
          output: 1000000,
        ),
        _event(
          id: 'unpriced',
          sessionId: 's2',
          model: 'unknown-model',
          input: 1000000,
          output: 0,
        ),
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

    expect(find.byKey(AppKeys.sessionUsageCostCard), findsOneWidget);
    expect(find.textContaining(r'$18.00'), findsWidgets);
    expect(find.textContaining('1 priced · 1 unpriced'), findsOneWidget);
    expect(find.text('Unpriced'), findsOneWidget);
    expect(find.text('Cost'), findsWidgets);
  });

  testWidgets('paginates session rows at 20 per page', (tester) async {
    _useTallViewport(tester);
    final cubit = _pagedCubit(25);
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    expect(find.text('Session 1'), findsOneWidget);
    expect(find.text('Session 20'), findsOneWidget);
    expect(find.text('Session 21'), findsNothing);
    expect(find.byKey(AppKeys.sessionUsagePageRange), findsOneWidget);
    expect(find.text('1–20 of 25 groups'), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.sessionUsageNextPage));
    await tester.pumpAndSettle();

    expect(find.text('Session 1'), findsNothing);
    expect(find.text('Session 20'), findsNothing);
    expect(find.text('Session 21'), findsOneWidget);
    expect(find.text('Session 25'), findsOneWidget);
    expect(find.text('21–25 of 25 groups'), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.sessionUsagePrevPage));
    await tester.pumpAndSettle();
    expect(find.text('Session 1'), findsOneWidget);
    expect(find.text('Session 21'), findsNothing);
  });

  testWidgets('search resets pagination to the first page', (tester) async {
    _useTallViewport(tester);
    final cubit = _pagedCubit(25);
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppKeys.sessionUsageNextPage));
    await tester.pumpAndSettle();
    expect(find.text('Session 21'), findsOneWidget);

    await tester.enterText(find.byKey(AppKeys.sessionUsageSearchField), '22');
    await tester.pumpAndSettle();

    expect(cubit.state.dashboard.rows.single.label, 'Session 22');
    expect(find.text('Session 22'), findsOneWidget);
    expect(find.text('Session 21'), findsNothing);
    expect(find.text('Session 23'), findsNothing);
  });

  testWidgets('page size selector changes the visible row count', (
    tester,
  ) async {
    _useTallViewport(tester);
    final cubit = _pagedCubit(25);
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();
    expect(find.text('Session 21'), findsNothing);

    await tester.tap(find.byKey(AppKeys.sessionUsagePageSize));
    await tester.pumpAndSettle();
    await tester.tap(find.text('50').last);
    await tester.pumpAndSettle();

    expect(find.text('Session 25'), findsOneWidget);
    expect(find.text('1–25 of 25 groups'), findsOneWidget);
  });

  testWidgets('hides pagination when rows fit on one page', (tester) async {
    final cubit = _pagedCubit(2);
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.sessionUsagePageRange), findsNothing);
    expect(find.byKey(AppKeys.sessionUsagePrevPage), findsNothing);
    expect(find.byKey(AppKeys.sessionUsageNextPage), findsNothing);
  });
}
