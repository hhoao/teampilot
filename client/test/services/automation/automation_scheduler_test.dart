import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/session/session_open_status.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/repositories/automation_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/automation/automation_bus_gateway.dart';
import 'package:teampilot/services/automation/automation_command_executor.dart';
import 'package:teampilot/services/automation/automation_command_runner.dart';
import 'package:teampilot/services/automation/automation_dispatcher.dart';
import 'package:teampilot/services/automation/automation_prompt_delivery.dart';
import 'package:teampilot/services/automation/automation_run_accounting.dart';
import 'package:teampilot/services/automation/automation_schedule_calculator.dart';
import 'package:teampilot/services/automation/automation_scheduler.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../../support/post_frame_test_harness.dart';

class _FakeSessionRepository implements SessionRepository {
  _FakeSessionRepository(this.sessions);

  final List<AppSession> sessions;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<AppSession>> loadSessionsForWorkspace(String workspaceId) async {
    return sessions
        .where((s) => s.workspaceId == workspaceId)
        .toList(growable: false);
  }
}

class _RecordingBusGateway implements AutomationBusGateway {
  var deliverCount = 0;

  @override
  Future<AutomationDeliveryOutcome> deliverUserCommandToMember(
    AppSession session,
    String memberId,
    String message,
  ) async {
    deliverCount++;
    return const AutomationDeliveryOutcome.delivered();
  }

  @override
  Future<void> ensureMemberReady(String sessionId, String memberId) async {}
}

Automation _dueAutomation({required int nextRunAtMs}) {
  return Automation(
    id: 'due-1',
    name: 'Ping',
    action: AutomationAction.scheduledMessage,
    workspaceId: 'ws1',
    isPersonal: false,
    teamId: 'team-1',
    sessionId: 'sess-1',
    message: 'hello',
    preset: AutomationSchedulePreset.daily,
    hourMinute: '09:00',
    timezone: 'UTC',
    dtstartMs: 1,
    enabled: true,
    nextRunAtMs: nextRunAtMs,
    createdAtMs: 1,
    updatedAtMs: 1,
  );
}

const _now = 10_000_000;

Automation _runCommandAutomation({
  AutomationCatchUpPolicy catchUpPolicy = AutomationCatchUpPolicy.none,
  int? nextRunAtMs,
  int timeoutSeconds = 300,
}) {
  return Automation(
    id: 'cmd-1',
    name: 'Nightly build',
    action: AutomationAction.runCommand,
    workspaceId: 'ws1',
    command: 'echo hi',
    timeoutSeconds: timeoutSeconds,
    catchUpPolicy: catchUpPolicy,
    message: '',
    preset: AutomationSchedulePreset.daily,
    hourMinute: '02:00',
    timezone: 'UTC',
    dtstartMs: 1,
    enabled: true,
    nextRunAtMs: nextRunAtMs,
    createdAtMs: 1,
    updatedAtMs: 1,
  );
}

class _NoopRunner implements AutomationCommandRunner {
  @override
  Future<AutomationCommandOutcome> run(AutomationCommandRequest request) async {
    return const AutomationCommandOutcome(exitCode: 0);
  }
}

class _RecordingCommandExecutor extends AutomationCommandExecutor {
  _RecordingCommandExecutor({
    required super.repository,
    required super.accounting,
    required super.runner,
  });

  int calls = 0;

  @override
  Future<AutomationRun?> enqueue(
    Automation automation, {
    AutomationRunTrigger trigger = AutomationRunTrigger.scheduled,
  }) async {
    calls += 1;
    return AutomationRun(
      id: 'run-$calls',
      automationId: automation.id,
      workspaceId: automation.workspaceId,
      scheduledForMs: automation.nextRunAtMs ?? 0,
      status: AutomationRunStatus.completed,
      trigger: trigger,
      startedAtMs: 0,
      completedAtMs: 0,
    );
  }
}

({
  AutomationScheduler scheduler,
  _RecordingCommandExecutor executor,
  AutomationRepository repo,
})
_buildCommandScheduler({
  required int nowMs,
  Duration tickInterval = const Duration(seconds: 30),
}) {
  final layout = WorkspaceLayout(
    teampilotRoot: testHomeStorage.paths.basePath,
    fs: testHomeStorage.fs,
  );
  final repo = AutomationRepository(fs: testHomeStorage.fs, layout: layout);
  final executor = _RecordingCommandExecutor(
    repository: repo,
    accounting: AutomationRunAccounting(AutomationScheduleCalculator()),
    runner: _NoopRunner(),
  );
  final scheduler = AutomationScheduler(
    repository: repo,
    dispatcher: _buildDispatcher(
      repo: repo,
      bus: _RecordingBusGateway(),
      sessions: const [],
    ),
    scheduleCalculator: AutomationScheduleCalculator(),
    commandExecutor: executor,
    tickInterval: tickInterval,
    nowMs: () => nowMs,
  );
  return (scheduler: scheduler, executor: executor, repo: repo);
}

AutomationDispatcher _buildDispatcher({
  required AutomationRepository repo,
  required _RecordingBusGateway bus,
  required List<AppSession> sessions,
}) {
  final workspace = Workspace(workspaceId: 'ws1', createdAt: 1);
  final team = TeamProfile(
    id: 'team-1',
    name: 'Team',
    members: const [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
  );
  return AutomationDispatcher(
    repository: repo,
    scheduleCalculator: AutomationScheduleCalculator(),
    sessionRepository: _FakeSessionRepository(sessions),
    busGateway: bus,
    requestOpenSession: (_) async => SessionOpenStatus.opened,
    requestCreateAndOpenSession: (_) async => SessionOpenStatus.opened,
    workspaceById: (_) => workspace,
    teamById: (id) => id == 'team-1' ? team : null,
    nowMs: () => 2_000,
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('runNow dispatches due automation once', () async {
    final layout = WorkspaceLayout(
      teampilotRoot: testHomeStorage.paths.basePath,
      fs: testHomeStorage.fs,
    );
    final repo = AutomationRepository(fs: testHomeStorage.fs, layout: layout);
    final bus = _RecordingBusGateway();
    final session = AppSession(
      sessionId: 'sess-1',
      workspaceId: 'ws1',
      sessionTeam: 'team-1',
      createdAt: 1,
    );
    await repo.upsert(_dueAutomation(nextRunAtMs: 1_000));

    final scheduler = AutomationScheduler(
      repository: repo,
      dispatcher: _buildDispatcher(repo: repo, bus: bus, sessions: [session]),
      scheduleCalculator: AutomationScheduleCalculator(),
      nowMs: () => 2_000,
    );

    await scheduler.runNow('ws1', 'due-1');

    expect(bus.deliverCount, 1);
  });

  test('runNow is blocked when run limit is reached', () async {
    final layout = WorkspaceLayout(
      teampilotRoot: testHomeStorage.paths.basePath,
      fs: testHomeStorage.fs,
    );
    final repo = AutomationRepository(fs: testHomeStorage.fs, layout: layout);
    final bus = _RecordingBusGateway();
    await repo.upsert(
      _dueAutomation(nextRunAtMs: 1_000).copyWith(
        maxRunCount: 1,
        runCount: 1,
        enabled: false,
        clearNextRunAtMs: true,
      ),
    );

    final scheduler = AutomationScheduler(
      repository: repo,
      dispatcher: _buildDispatcher(repo: repo, bus: bus, sessions: const []),
      scheduleCalculator: AutomationScheduleCalculator(),
      nowMs: () => 2_000,
    );

    await scheduler.runNow('ws1', 'due-1');

    expect(bus.deliverCount, 0);
  });

  test('marks missed run outside grace and advances schedule', () async {
    final layout = WorkspaceLayout(
      teampilotRoot: testHomeStorage.paths.basePath,
      fs: testHomeStorage.fs,
    );
    final repo = AutomationRepository(fs: testHomeStorage.fs, layout: layout);
    final bus = _RecordingBusGateway();
    await repo.upsert(
      _dueAutomation(nextRunAtMs: 1_000).copyWith(missedRunGraceMinutes: 15),
    );

    final scheduler = AutomationScheduler(
      repository: repo,
      dispatcher: _buildDispatcher(repo: repo, bus: bus, sessions: const []),
      scheduleCalculator: AutomationScheduleCalculator(),
      nowMs: () => 1_000 + (16 * 60 * 1000),
    );

    scheduler.start();
    await scheduler.waitForIdle();
    scheduler.stop();

    final runs = await repo.runsFor('ws1', automationId: 'due-1');
    expect(
      runs.any((r) => r.status == AutomationRunStatus.skippedMissed),
      isTrue,
    );
    final updated = (await repo.listForWorkspace('ws1')).single;
    expect(updated.nextRunAtMs, isNotNull);
    expect(updated.nextRunAtMs! > 1_000, isTrue);
    expect(bus.deliverCount, 0);
  });

  test('disables expired once automation missed beyond grace', () async {
    final layout = WorkspaceLayout(
      teampilotRoot: testHomeStorage.paths.basePath,
      fs: testHomeStorage.fs,
    );
    final repo = AutomationRepository(fs: testHomeStorage.fs, layout: layout);
    final bus = _RecordingBusGateway();
    await repo.upsert(
      _dueAutomation(nextRunAtMs: 1_000).copyWith(
        preset: AutomationSchedulePreset.once,
        runAtMs: 1_000,
        missedRunGraceMinutes: 15,
      ),
    );

    final scheduler = AutomationScheduler(
      repository: repo,
      dispatcher: _buildDispatcher(repo: repo, bus: bus, sessions: const []),
      scheduleCalculator: AutomationScheduleCalculator(),
      nowMs: () => 1_000 + (16 * 60 * 1000),
    );

    scheduler.start();
    await scheduler.waitForIdle();
    scheduler.stop();

    final runs = await repo.runsFor('ws1', automationId: 'due-1');
    expect(
      runs.any((r) => r.status == AutomationRunStatus.skippedMissed),
      isTrue,
    );
    final updated = (await repo.listForWorkspace('ws1')).single;
    expect(updated.enabled, isFalse);
    expect(updated.nextRunAtMs, isNull);
    expect(bus.deliverCount, 0);
  });

  test('dispatches once automation missed within grace', () async {
    final layout = WorkspaceLayout(
      teampilotRoot: testHomeStorage.paths.basePath,
      fs: testHomeStorage.fs,
    );
    final repo = AutomationRepository(fs: testHomeStorage.fs, layout: layout);
    final bus = _RecordingBusGateway();
    final session = AppSession(
      sessionId: 'sess-1',
      workspaceId: 'ws1',
      sessionTeam: 'team-1',
      createdAt: 1,
    );
    await repo.upsert(
      _dueAutomation(nextRunAtMs: 1_000).copyWith(
        preset: AutomationSchedulePreset.once,
        runAtMs: 1_000,
        missedRunGraceMinutes: 15,
      ),
    );

    final scheduler = AutomationScheduler(
      repository: repo,
      dispatcher: _buildDispatcher(repo: repo, bus: bus, sessions: [session]),
      scheduleCalculator: AutomationScheduleCalculator(),
      nowMs: () => 1_000 + (5 * 60 * 1000),
    );

    scheduler.start();
    await scheduler.waitForIdle();
    scheduler.stop();

    expect(bus.deliverCount, 1);
    final updated = (await repo.listForWorkspace('ws1')).single;
    expect(updated.enabled, isFalse);
    expect(updated.nextRunAtMs, isNull);
  });

  test(
    'catch-up once dispatches a missed runCommand instead of skipping',
    () async {
      final harness = _buildCommandScheduler(nowMs: _now);
      await harness.repo.upsert(
        _runCommandAutomation(
          catchUpPolicy: AutomationCatchUpPolicy.once,
          nextRunAtMs: _now - const Duration(hours: 2).inMilliseconds,
        ),
      );

      harness.scheduler.start();
      await harness.scheduler.waitForIdle();
      harness.scheduler.stop();

      final runs = await harness.repo.runsFor('ws1');
      expect(
        runs.any((r) => r.status == AutomationRunStatus.skippedMissed),
        isFalse,
      );
      expect(harness.executor.calls, 1);
    },
  );

  test('catch-up none keeps skipping', () async {
    final harness = _buildCommandScheduler(nowMs: _now);
    await harness.repo.upsert(
      _runCommandAutomation(
        catchUpPolicy: AutomationCatchUpPolicy.none,
        nextRunAtMs: _now - const Duration(hours: 2).inMilliseconds,
      ),
    );

    harness.scheduler.start();
    await harness.scheduler.waitForIdle();
    harness.scheduler.stop();

    final runs = await harness.repo.runsFor('ws1');
    expect(runs.single.status, AutomationRunStatus.skippedMissed);
    expect(harness.executor.calls, 0);
  });

  test('marks stale dispatching runs as interrupted on start', () async {
    final harness = _buildCommandScheduler(nowMs: _now);
    final automation = _runCommandAutomation(timeoutSeconds: 30);
    await harness.repo.upsert(automation);
    await harness.repo.upsertRun(
      'ws1',
      AutomationRun(
        id: 'stale',
        automationId: automation.id,
        workspaceId: 'ws1',
        scheduledForMs: _now - const Duration(hours: 1).inMilliseconds,
        status: AutomationRunStatus.dispatching,
        trigger: AutomationRunTrigger.scheduled,
        startedAtMs: _now - const Duration(hours: 1).inMilliseconds,
      ),
    );

    harness.scheduler.start();
    await harness.scheduler.waitForIdle();
    harness.scheduler.stop();

    final runs = await harness.repo.runsFor('ws1');
    final stale = runs.firstWhere((r) => r.id == 'stale');
    expect(stale.status, AutomationRunStatus.dispatchFailed);
    expect(stale.error, 'interrupted');
  });

  test(
    'marks a recently started dispatching run as interrupted on start',
    () async {
      final harness = _buildCommandScheduler(nowMs: _now);
      final automation = _runCommandAutomation(timeoutSeconds: 300);
      await harness.repo.upsert(automation);
      await harness.repo.upsertRun(
        'ws1',
        AutomationRun(
          id: 'recent',
          automationId: automation.id,
          workspaceId: 'ws1',
          scheduledForMs: _now - 1000,
          status: AutomationRunStatus.dispatching,
          trigger: AutomationRunTrigger.scheduled,
          startedAtMs: _now - 1000,
        ),
      );

      harness.scheduler.start();
      await harness.scheduler.waitForIdle();
      harness.scheduler.stop();

      // Nothing executes in a fresh process, so even a run that started
      // seconds ago is stale and must not stay `dispatching` forever.
      final runs = await harness.repo.runsFor('ws1');
      final recent = runs.firstWhere((r) => r.id == 'recent');
      expect(recent.status, AutomationRunStatus.dispatchFailed);
      expect(recent.error, 'interrupted');
    },
  );

  test(
    'tick path skips an overdue runCommand beyond grace without catch-up',
    () async {
      final harness = _buildCommandScheduler(
        nowMs: _now,
        tickInterval: const Duration(milliseconds: 20),
      );
      final automation = _runCommandAutomation(
        nextRunAtMs: _now + const Duration(minutes: 1).inMilliseconds,
      );
      await harness.repo.upsert(automation);

      harness.scheduler.start();
      await harness.scheduler.waitForIdle();
      expect(harness.executor.calls, 0);

      // Simulate a laptop resume: the next slot is now hours overdue and the
      // periodic tick (not the one-shot startup pass) observes it.
      await harness.repo.upsert(
        automation.copyWith(
          nextRunAtMs: _now - const Duration(hours: 2).inMilliseconds,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      harness.scheduler.stop();
      await harness.scheduler.waitForIdle();

      final runs = await harness.repo.runsFor('ws1');
      expect(runs.single.status, AutomationRunStatus.skippedMissed);
      expect(harness.executor.calls, 0);
    },
  );

  test('scheduled runCommand records the due slot as scheduledForMs', () async {
    final layout = WorkspaceLayout(
      teampilotRoot: testHomeStorage.paths.basePath,
      fs: testHomeStorage.fs,
    );
    final repo = AutomationRepository(fs: testHomeStorage.fs, layout: layout);
    final executor = AutomationCommandExecutor(
      repository: repo,
      accounting: AutomationRunAccounting(AutomationScheduleCalculator()),
      runner: _NoopRunner(),
      nowMs: () => _now,
    );
    final scheduler = AutomationScheduler(
      repository: repo,
      dispatcher: _buildDispatcher(
        repo: repo,
        bus: _RecordingBusGateway(),
        sessions: const [],
      ),
      scheduleCalculator: AutomationScheduleCalculator(),
      commandExecutor: executor,
      nowMs: () => _now,
    );
    final dueSlot = _now - const Duration(hours: 2).inMilliseconds;
    final automation = _runCommandAutomation(
      catchUpPolicy: AutomationCatchUpPolicy.once,
      nextRunAtMs: dueSlot,
    );
    await repo.upsert(automation);

    scheduler.start();
    await scheduler.waitForIdle();
    await executor.waitForIdle();
    scheduler.stop();

    final runs = await repo.runsFor('ws1');
    expect(runs.single.scheduledForMs, dueSlot);
    expect(runs.single.status, AutomationRunStatus.completed);
    final stored = (await repo.listForWorkspace('ws1')).single;
    expect(stored.runCount, 1);
    expect(
      stored.nextRunAtMs,
      AutomationScheduleCalculator().computeNextRunAtMs(
        automation,
        afterMs: _now,
      ),
    );
  });
}
