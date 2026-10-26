import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session_usage_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/usage/session_usage_sync_service.dart';

final _now = DateTime(2026, 10, 26, 18);

SessionUsageEvent _event({
  String id = 'r1',
  String sessionId = 's1',
  int input = 10,
  int output = 2,
  int? timestampMs,
}) {
  return SessionUsageEvent(
    requestId: id,
    cli: CliTool.claude,
    model: 'claude-sonnet-4',
    inputTokens: input,
    outputTokens: output,
    cacheReadTokens: 0,
    cacheCreationTokens: 0,
    inputSemantics: UsageInputSemantics.fresh,
    timestampMs: timestampMs ?? _now.millisecondsSinceEpoch,
    sessionId: sessionId,
  );
}

AppSession _session(String id, String display) => AppSession(
  sessionId: id,
  workspaceId: 'w1',
  display: display,
  createdAt: 1,
);

void main() {
  test('loads cached events and attribution', () async {
    final cubit = SessionUsageCubit(
      loadEvents: () async => [_event()],
      syncAll: () async => const UsageSyncResult(),
      loadSessions: () async => [_session('s1', 'Alpha')],
      loadTeams: () async => const <TeamProfile>[],
      now: () => _now,
    );
    addTearDown(cubit.close);

    await cubit.ensureLoaded();

    expect(cubit.state.status, SessionUsageStatus.ready);
    expect(cubit.state.dashboard.summary.requests, 1);
    expect(cubit.state.dashboard.summary.totalTokens, 12);
    expect(cubit.state.dashboard.rows.single.label, 'Alpha');
  });

  test('ensureLoaded and reload are single-flight', () async {
    final completer = Completer<List<SessionUsageEvent>>();
    var loadCount = 0;
    final cubit = SessionUsageCubit(
      loadEvents: () {
        loadCount++;
        return completer.future;
      },
      syncAll: () async => const UsageSyncResult(),
      loadSessions: () async => const <AppSession>[],
      loadTeams: () async => const <TeamProfile>[],
      now: () => _now,
    );
    addTearDown(cubit.close);

    final first = cubit.ensureLoaded();
    final second = cubit.ensureLoaded();
    expect(loadCount, 1);

    completer.complete([_event()]);
    await Future.wait([first, second]);
    expect(cubit.state.status, SessionUsageStatus.ready);

    await cubit.ensureLoaded();
    expect(loadCount, 1);
  });

  test('filters recompute without reloading events', () async {
    var loadCount = 0;
    final cubit = SessionUsageCubit(
      loadEvents: () async {
        loadCount++;
        return [
          _event(id: 'a', sessionId: 's1'),
          _event(id: 'b', sessionId: 's2', input: 100),
        ];
      },
      syncAll: () async => const UsageSyncResult(),
      loadSessions: () async => [
        _session('s1', 'Alpha'),
        _session('s2', 'Beta'),
      ],
      loadTeams: () async => const <TeamProfile>[],
      now: () => _now,
    );
    addTearDown(cubit.close);

    await cubit.ensureLoaded();
    expect(loadCount, 1);
    expect(cubit.state.dashboard.rows, hasLength(2));

    cubit.setRange(UsageRange.today);
    cubit.setGroupBy(UsageGroupBy.model);
    cubit.setQuery('claude');
    await Future<void>.delayed(Duration.zero);

    expect(loadCount, 1);
    expect(cubit.state.range, UsageRange.today);
    expect(cubit.state.groupBy, UsageGroupBy.model);
    expect(cubit.state.query, 'claude');
    expect(cubit.state.dashboard.rows, hasLength(1));

    cubit.setCli(CliTool.codex);
    expect(cubit.state.dashboard.summary.requests, 0);

    cubit.resetFilters();
    expect(cubit.state.range, UsageRange.all);
    expect(cubit.state.cli, isNull);
    expect(cubit.state.query, '');
    expect(loadCount, 1);
  });

  test('sync reloads, records time/result, and clears errors', () async {
    var events = [_event()];
    final cubit = SessionUsageCubit(
      loadEvents: () async => events,
      syncAll: () async {
        events = [_event(), _event(id: 'r2', input: 20, output: 4)];
        return const UsageSyncResult(inserted: 1);
      },
      loadSessions: () async => const <AppSession>[],
      loadTeams: () async => const <TeamProfile>[],
      now: () => _now,
    );
    addTearDown(cubit.close);

    await cubit.ensureLoaded();
    await cubit.sync();

    expect(cubit.state.isSyncing, isFalse);
    expect(cubit.state.lastSyncAtMs, _now.millisecondsSinceEpoch);
    expect(cubit.state.lastSyncResult?.inserted, 1);
    expect(cubit.state.syncErrors, isEmpty);
    expect(cubit.state.syncFailed, isFalse);
    expect(cubit.state.dashboard.summary.requests, 2);
  });

  test('partial sync errors keep data visible', () async {
    final cubit = SessionUsageCubit(
      loadEvents: () async => [_event()],
      syncAll: () async => const UsageSyncResult(
        errors: [UsageSyncError(sourceId: 'src', message: 'bad')],
      ),
      loadSessions: () async => const <AppSession>[],
      loadTeams: () async => const <TeamProfile>[],
      now: () => _now,
    );
    addTearDown(cubit.close);

    await cubit.ensureLoaded();
    await cubit.sync();

    expect(cubit.state.hasData, isTrue);
    expect(cubit.state.hasSyncProblem, isTrue);
    expect(cubit.state.syncErrors.single.sourceId, 'src');
    expect(cubit.state.dashboard.summary.requests, 1);
  });

  test('fatal sync keeps the old dashboard and marks failure', () async {
    final cubit = SessionUsageCubit(
      loadEvents: () async => [_event()],
      syncAll: () async => throw StateError('offline'),
      loadSessions: () async => const <AppSession>[],
      loadTeams: () async => const <TeamProfile>[],
      now: () => _now,
    );
    addTearDown(cubit.close);

    await cubit.ensureLoaded();
    final before = cubit.state.dashboard.summary.totalTokens;
    await cubit.sync();

    expect(cubit.state.syncFailed, isTrue);
    expect(cubit.state.isSyncing, isFalse);
    expect(cubit.state.dashboard.summary.totalTokens, before);
    expect(cubit.state.lastSyncAtMs, isNull);
  });

  test('storage plane changes trigger a reload', () async {
    final changes = StreamController<void>();
    var loadCount = 0;
    final cubit = SessionUsageCubit(
      loadEvents: () async {
        loadCount++;
        return [_event()];
      },
      syncAll: () async => const UsageSyncResult(),
      loadSessions: () async => const <AppSession>[],
      loadTeams: () async => const <TeamProfile>[],
      storageChanges: changes.stream,
      now: () => _now,
    );
    addTearDown(() async {
      await changes.close();
      await cubit.close();
    });

    await cubit.ensureLoaded();
    expect(loadCount, 1);

    changes.add(null);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(loadCount, 2);
  });

  test('sync is single-flight', () async {
    final syncCompleter = Completer<UsageSyncResult>();
    var syncCount = 0;
    final cubit = SessionUsageCubit(
      loadEvents: () async => const <SessionUsageEvent>[],
      syncAll: () {
        syncCount++;
        return syncCompleter.future;
      },
      loadSessions: () async => const <AppSession>[],
      loadTeams: () async => const <TeamProfile>[],
      now: () => _now,
    );
    addTearDown(cubit.close);

    final first = cubit.sync();
    final second = cubit.sync();
    expect(syncCount, 1);
    syncCompleter.complete(const UsageSyncResult());
    await Future.wait([first, second]);
    expect(cubit.state.isSyncing, isFalse);
  });
}
