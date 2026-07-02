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
  void deliverUserCommandToMember(
    String sessionId,
    String memberId,
    String message,
  ) {
    deliverCalls.add((sessionId, memberId, message));
  }

  @override
  Future<void> ensureMemberReady(String sessionId, String memberId) async {
    ensureCalls.add((sessionId, memberId));
  }
}

Automation _sendToLeadAutomation({
  required String sessionId,
  String workspaceId = 'ws1',
}) {
  return Automation(
    id: 'auto-1',
    name: 'Reset',
    action: AutomationAction.sendToLead,
    scope: AutomationScope.session,
    workspaceId: workspaceId,
    sessionId: sessionId,
    targetMemberId: 'team-lead',
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

  test('sendToLead delivers message when session is connected', () async {
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
      members: const [
        TeamMemberConfig(id: 'team-lead', name: 'Lead'),
      ],
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

    final result = await dispatcher.dispatch(_sendToLeadAutomation(sessionId: 'sess-1'));

    expect(openCalls, 1);
    expect(bus.ensureCalls, [('sess-1', 'team-lead')]);
    expect(bus.deliverCalls, [('sess-1', 'team-lead', '/clear')]);
    expect(result.run.status, AutomationRunStatus.completed);
    expect(result.automation.lastRunAtMs, 100);
    final runs = await repo.runsFor('ws1', automationId: 'auto-1');
    expect(runs, hasLength(1));
  });

  test('sendToLead skips when session is missing', () async {
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

    final result = await dispatcher.dispatch(_sendToLeadAutomation(sessionId: 'missing'));

    expect(result.run.status, AutomationRunStatus.skippedUnavailable);
    expect(result.run.error, 'session_not_found');
    expect(bus.deliverCalls, isEmpty);
  });

  test('sendToLead fails when member connect times out', () async {
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

    final result = await dispatcher.dispatch(_sendToLeadAutomation(sessionId: 'sess-2'));

    expect(result.run.status, AutomationRunStatus.dispatchFailed);
    expect(result.run.error, 'member_connect_timeout');
  });
}

class _SlowBusGateway implements AutomationBusGateway {
  @override
  void deliverUserCommandToMember(
    String sessionId,
    String memberId,
    String message,
  ) {}

  @override
  Future<void> ensureMemberReady(String sessionId, String memberId) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}
