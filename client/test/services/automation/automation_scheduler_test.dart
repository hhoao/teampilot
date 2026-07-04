import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/session_open_status.dart';
import 'package:teampilot/models/automation_tab_scope.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/repositories/automation_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/automation/automation_bus_gateway.dart';
import 'package:teampilot/services/automation/automation_dispatcher.dart';
import 'package:teampilot/services/automation/automation_schedule_calculator.dart';
import 'package:teampilot/services/automation/automation_scheduler.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../../support/automation_test_fixtures.dart';
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
  Future<void> deliverUserCommandToMember(
    String sessionId,
    String memberId,
    String message,
  ) async {
    deliverCount++;
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
    launchProfileId: 'team-1',
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

AutomationDispatcher _buildDispatcher({
  required AutomationRepository repo,
  required _RecordingBusGateway bus,
  required List<AppSession> sessions,
}) {
  final workspace = Workspace(workspaceId: 'ws1', createdAt: 1);
  final team = TeamProfile(
    id: 'team-1',
    name: 'Team',
    members: const [
      TeamMemberConfig(id: 'team-lead', name: 'Lead'),
    ],
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
    launchProfileKindById: testLaunchProfileKindResolver(),
    nowMs: () => 2_000,
  );
}

const _teamTabScope = AutomationTabScope(
  workspaceId: 'ws1',
  launchProfileId: 'team-1',
);

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('runNow dispatches due automation once', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
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
      dispatcher: _buildDispatcher(
        repo: repo,
        bus: bus,
        sessions: [session],
      ),
      scheduleCalculator: AutomationScheduleCalculator(),
      nowMs: () => 2_000,
    );

    await scheduler.runNow(_teamTabScope, 'due-1');

    expect(bus.deliverCount, 1);
  });

  test('runNow is blocked when run limit is reached', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
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
      dispatcher: _buildDispatcher(
        repo: repo,
        bus: bus,
        sessions: const [],
      ),
      scheduleCalculator: AutomationScheduleCalculator(),
      nowMs: () => 2_000,
    );

    await scheduler.runNow(_teamTabScope, 'due-1');

    expect(bus.deliverCount, 0);
  });

  test('marks missed run outside grace and advances schedule', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    final bus = _RecordingBusGateway();
    await repo.upsert(
      _dueAutomation(nextRunAtMs: 1_000).copyWith(
        missedRunGraceMinutes: 15,
      ),
    );

    final scheduler = AutomationScheduler(
      repository: repo,
      dispatcher: _buildDispatcher(
        repo: repo,
        bus: bus,
        sessions: const [],
      ),
      scheduleCalculator: AutomationScheduleCalculator(),
      nowMs: () => 1_000 + (16 * 60 * 1000),
    );

    scheduler.start();
    await scheduler.waitForIdle();
    scheduler.stop();

    final runs = await repo.runsFor(_teamTabScope, automationId: 'due-1');
    expect(runs.any((r) => r.status == AutomationRunStatus.skippedMissed), isTrue);
    final updated = (await repo.listForTabScope(_teamTabScope)).single;
    expect(updated.nextRunAtMs, isNotNull);
    expect(updated.nextRunAtMs! > 1_000, isTrue);
    expect(bus.deliverCount, 0);
  });
}
