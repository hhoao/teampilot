import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/session_open_status.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/repositories/automation_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/automation/automation_bus_gateway.dart';
import 'package:teampilot/services/automation/automation_dispatcher.dart';
import 'package:teampilot/services/automation/automation_schedule_calculator.dart';
import 'package:teampilot/services/storage/app_storage.dart';
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
  final deliverCalls = <(String sessionId, String memberId, String message)>[];
  final ensureCalls = <(String sessionId, String memberId)>[];

  @override
  Future<void> deliverUserCommandToMember(
    String sessionId,
    String memberId,
    String message,
  ) async {
    deliverCalls.add((sessionId, memberId, message));
  }

  @override
  Future<void> ensureMemberReady(String sessionId, String memberId) async {
    ensureCalls.add((sessionId, memberId));
  }
}

Automation _scheduledMessageAutomation({
  required String sessionId,
  String workspaceId = 'ws1',
  String teamId = 'team-1',
}) {
  return Automation(
    id: 'auto-1',
    name: 'Reset',
    action: AutomationAction.scheduledMessage,
    workspaceId: workspaceId,
    isPersonal: false,
    teamId: teamId,
    sessionId: sessionId,
    message: '/clear',
    preset: AutomationSchedulePreset.hourly,
    minute: 0,
    hourMinute: '09:00',
    timezone: 'UTC',
    dtstartMs: 1,
    enabled: true,
    nextRunAtMs: 1,
    createdAtMs: 1,
    updatedAtMs: 1,
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('scheduledMessage delivers message when session is connected', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    final session = AppSession(
      sessionId: 'sess-1',
      workspaceId: 'ws1',
      sessionTeam: 'team-1',
      createdAt: 1,
    );
    final workspace = Workspace(workspaceId: 'ws1', createdAt: 1);
    final team = TeamProfile(
      id: 'team-1',
      name: 'Team',
      members: const [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
    );
    final bus = _RecordingBusGateway();
    var openCalls = 0;

    final dispatcher = AutomationDispatcher(
      repository: repo,
      scheduleCalculator: AutomationScheduleCalculator(),
      sessionRepository: _FakeSessionRepository([session]),
      busGateway: bus,
      requestOpenSession: (request) async {
        openCalls++;
        expect(request.session.sessionId, 'sess-1');
        return SessionOpenStatus.opened;
      },
      requestCreateAndOpenSession: (_) async => SessionOpenStatus.opened,
      workspaceById: (_) => workspace,
      teamById: (id) => id == 'team-1' ? team : null,
      nowMs: () => 100,
    );

    final result = await dispatcher.dispatch(
      _scheduledMessageAutomation(sessionId: 'sess-1'),
    );

    expect(openCalls, 1);
    expect(bus.ensureCalls, [('sess-1', 'team-lead')]);
    expect(bus.deliverCalls, [('sess-1', 'team-lead', '/clear')]);
    expect(result.run.status, AutomationRunStatus.completed);
    expect(result.automation.lastRunAtMs, 100);
    final runs = await repo.runsFor('ws1', automationId: 'auto-1');
    expect(runs, hasLength(1));
  });

  test('scheduledMessage wraps ensure+deliver in runDeliveryInFlight', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    final session = AppSession(
      sessionId: 'sess-1',
      workspaceId: 'ws1',
      sessionTeam: 'team-1',
      createdAt: 1,
    );
    final workspace = Workspace(workspaceId: 'ws1', createdAt: 1);
    final team = TeamProfile(
      id: 'team-1',
      name: 'Team',
      members: const [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
    );
    final bus = _RecordingBusGateway();
    final events = <String>[];

    final dispatcher = AutomationDispatcher(
      repository: repo,
      scheduleCalculator: AutomationScheduleCalculator(),
      sessionRepository: _FakeSessionRepository([session]),
      busGateway: bus,
      requestOpenSession: (_) async => SessionOpenStatus.opened,
      requestCreateAndOpenSession: (_) async => SessionOpenStatus.opened,
      workspaceById: (_) => workspace,
      teamById: (id) => id == 'team-1' ? team : null,
      nowMs: () => 100,
      runDeliveryInFlight: <T>(sessionId, action) async {
        events.add('begin:$sessionId');
        try {
          return await action();
        } finally {
          events.add('end:$sessionId');
        }
      },
    );

    await dispatcher.dispatch(
      _scheduledMessageAutomation(sessionId: 'sess-1'),
    );

    expect(events, ['begin:sess-1', 'end:sess-1']);
    expect(bus.ensureCalls, [('sess-1', 'team-lead')]);
    expect(bus.deliverCalls, [('sess-1', 'team-lead', '/clear')]);
    expect(events.indexOf('begin:sess-1'), lessThan(events.indexOf('end:sess-1')));
  });

  test('scheduledMessage skips when session is missing', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    final bus = _RecordingBusGateway();

    final dispatcher = AutomationDispatcher(
      repository: repo,
      scheduleCalculator: AutomationScheduleCalculator(),
      sessionRepository: _FakeSessionRepository(const []),
      busGateway: bus,
      requestOpenSession: (_) async => SessionOpenStatus.opened,
      requestCreateAndOpenSession: (_) async => SessionOpenStatus.opened,
      workspaceById: (_) => null,
      teamById: (_) => null,
      nowMs: () => 50,
    );

    final result = await dispatcher.dispatch(
      _scheduledMessageAutomation(sessionId: 'missing'),
    );

    expect(result.run.status, AutomationRunStatus.skippedUnavailable);
    expect(result.run.error, 'session_not_found');
    expect(bus.deliverCalls, isEmpty);
  });

  test('scheduledMessage fails when member connect times out', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    final session = AppSession(
      sessionId: 'sess-2',
      workspaceId: 'ws1',
      sessionTeam: 'team-1',
      createdAt: 1,
    );
    final workspace = Workspace(workspaceId: 'ws1', createdAt: 1);

    final dispatcher = AutomationDispatcher(
      repository: repo,
      scheduleCalculator: AutomationScheduleCalculator(),
      sessionRepository: _FakeSessionRepository([session]),
      busGateway: _SlowBusGateway(),
      requestOpenSession: (_) async => SessionOpenStatus.opened,
      requestCreateAndOpenSession: (_) async => SessionOpenStatus.opened,
      workspaceById: (_) => workspace,
      teamById: (_) => null,
      nowMs: () => 10,
      memberReadyTimeout: const Duration(milliseconds: 50),
    );

    final result = await dispatcher.dispatch(
      _scheduledMessageAutomation(sessionId: 'sess-2'),
    );

    expect(result.run.status, AutomationRunStatus.dispatchFailed);
    expect(result.run.error, 'member_not_ready');
  });

  test('dispatch increments runCount and disables at maxRunCount', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    final session = AppSession(
      sessionId: 'sess-1',
      workspaceId: 'ws1',
      sessionTeam: 'team-1',
      createdAt: 1,
    );
    final workspace = Workspace(workspaceId: 'ws1', createdAt: 1);
    final team = TeamProfile(
      id: 'team-1',
      name: 'Team',
      members: const [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
    );
    final bus = _RecordingBusGateway();

    final dispatcher = AutomationDispatcher(
      repository: repo,
      scheduleCalculator: AutomationScheduleCalculator(),
      sessionRepository: _FakeSessionRepository([session]),
      busGateway: bus,
      requestOpenSession: (_) async => SessionOpenStatus.opened,
      requestCreateAndOpenSession: (_) async => SessionOpenStatus.opened,
      workspaceById: (_) => workspace,
      teamById: (id) => id == 'team-1' ? team : null,
      nowMs: () => 100,
    );

    final automation = _scheduledMessageAutomation(
      sessionId: 'sess-1',
    ).copyWith(maxRunCount: 1);
    final result = await dispatcher.dispatch(automation);

    expect(result.automation.runCount, 1);
    expect(result.automation.enabled, isFalse);
    expect(result.automation.nextRunAtMs, isNull);
  });

  test('launchPrompt with reuse binds session after first dispatch', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    final workspace = Workspace(workspaceId: 'ws1', createdAt: 1);
    final bus = _RecordingBusGateway();
    var createCalls = 0;
    String? createdSessionId;

    final dispatcher = AutomationDispatcher(
      repository: repo,
      scheduleCalculator: AutomationScheduleCalculator(),
      sessionRepository: _FakeSessionRepository(const []),
      busGateway: bus,
      requestOpenSession: (request) async {
        expect(request.session.sessionId, createdSessionId);
        return SessionOpenStatus.opened;
      },
      requestCreateAndOpenSession: (request) async {
        createCalls++;
        createdSessionId = request.fixedSessionId;
        return SessionOpenStatus.opened;
      },
      workspaceById: (_) => workspace,
      teamById: (_) => null,
      sessionById: (sessionId, workspaceId) {
        if (createdSessionId == null || sessionId != createdSessionId) {
          return null;
        }
        return AppSession(
          sessionId: sessionId,
          workspaceId: workspaceId,
          createdAt: 1,
        );
      },
      nowMs: () => 100,
    );

    final automation = Automation(
      id: 'launch-1',
      name: 'Daily prompt',
      action: AutomationAction.launchPrompt,
      workspaceId: 'ws1',
      isPersonal: true,
      presetId: 'preset-1',
      message: 'summarize inbox',
      reuseSession: true,
      preset: AutomationSchedulePreset.daily,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 1,
      enabled: true,
      nextRunAtMs: 1,
      createdAtMs: 1,
      updatedAtMs: 1,
    );

    final result = await dispatcher.dispatch(automation);

    expect(createCalls, 1);
    expect(result.run.status, AutomationRunStatus.completed);
    expect(createdSessionId, isNotNull);
    expect(result.automation.sessionId, createdSessionId);
    final persisted = await repo.listForWorkspace('ws1');
    expect(persisted.single.sessionId, createdSessionId);
  });

  test('launchPrompt passes automation working directory to session create', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    final workspace = Workspace(
      workspaceId: 'ws1',
      createdAt: 1,
    );
    final bus = _RecordingBusGateway();
    String? capturedWorkingDirectory;

    final dispatcher = AutomationDispatcher(
      repository: repo,
      scheduleCalculator: AutomationScheduleCalculator(),
      sessionRepository: _FakeSessionRepository(const []),
      busGateway: bus,
      requestOpenSession: (_) async => SessionOpenStatus.opened,
      requestCreateAndOpenSession: (request) async {
        capturedWorkingDirectory = request.workingDirectory;
        return SessionOpenStatus.opened;
      },
      workspaceById: (_) => workspace,
      teamById: (_) => null,
      sessionById: (sessionId, workspaceId) => AppSession(
        sessionId: sessionId,
        workspaceId: workspaceId,
        createdAt: 1,
      ),
      nowMs: () => 100,
    );

    final automation = Automation(
      id: 'launch-3',
      name: 'Worktree prompt',
      action: AutomationAction.launchPrompt,
      workspaceId: 'ws1',
      isPersonal: true,
      presetId: 'preset-1',
      projectFolderPath: '/repo',
      workingDirectoryPath: '/repo/feature',
      message: 'run',
      preset: AutomationSchedulePreset.daily,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 1,
      enabled: true,
      nextRunAtMs: 1,
      createdAtMs: 1,
      updatedAtMs: 1,
    );

    await dispatcher.dispatch(automation);

    expect(capturedWorkingDirectory, '/repo/feature');
  });

  test('launchPrompt with reuse reopens bound session on later runs', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    final session = AppSession(
      sessionId: 'bound-sess',
      workspaceId: 'ws1',
      createdAt: 1,
    );
    final workspace = Workspace(workspaceId: 'ws1', createdAt: 1);
    final bus = _RecordingBusGateway();
    var createCalls = 0;
    var openCalls = 0;

    final dispatcher = AutomationDispatcher(
      repository: repo,
      scheduleCalculator: AutomationScheduleCalculator(),
      sessionRepository: _FakeSessionRepository([session]),
      busGateway: bus,
      requestOpenSession: (request) async {
        openCalls++;
        expect(request.session.sessionId, 'bound-sess');
        expect(request.connectImmediately, isTrue);
        return SessionOpenStatus.opened;
      },
      requestCreateAndOpenSession: (_) async {
        createCalls++;
        return SessionOpenStatus.opened;
      },
      workspaceById: (_) => workspace,
      teamById: (_) => null,
      nowMs: () => 200,
    );

    final automation = Automation(
      id: 'launch-2',
      name: 'Reuse',
      action: AutomationAction.launchPrompt,
      workspaceId: 'ws1',
      isPersonal: true,
      presetId: 'preset-1',
      sessionId: 'bound-sess',
      message: 'continue',
      reuseSession: true,
      preset: AutomationSchedulePreset.daily,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 1,
      enabled: true,
      nextRunAtMs: 1,
      createdAtMs: 1,
      updatedAtMs: 1,
    );

    final result = await dispatcher.dispatch(automation);

    expect(createCalls, 0);
    expect(openCalls, 1);
    expect(result.run.status, AutomationRunStatus.completed);
    expect(result.automation.sessionId, 'bound-sess');
  });
}

class _SlowBusGateway implements AutomationBusGateway {
  @override
  Future<void> deliverUserCommandToMember(
    String sessionId,
    String memberId,
    String message,
  ) async {}

  @override
  Future<void> ensureMemberReady(String sessionId, String memberId) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}
