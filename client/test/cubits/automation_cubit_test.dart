import 'package:teampilot/models/automation_tab_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/automation_state.dart';
import 'package:teampilot/cubits/chat/model/session_open_status.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/repositories/automation_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/automation/automation_bus_gateway.dart';
import 'package:teampilot/services/automation/automation_dispatcher.dart';
import 'package:teampilot/services/automation/automation_schedule_calculator.dart';
import 'package:teampilot/services/automation/automation_scheduler.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../support/automation_test_fixtures.dart';
import '../support/post_frame_test_harness.dart';

class _FakeSessionRepository implements SessionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<AppSession>> loadSessionsForWorkspace(String workspaceId) async =>
      const [];
}

class _NoopBusGateway implements AutomationBusGateway {
  @override
  Future<void> deliverUserCommandToMember(
    String sessionId,
    String memberId,
    String message,
  ) async {}

  @override
  Future<void> ensureMemberReady(String sessionId, String memberId) async {}
}

Automation _sampleAutomation({
  required String id,
  bool enabled = true,
  int? nextRunAtMs,
}) {
  return Automation(
    id: id,
    name: 'Test $id',
    action: AutomationAction.scheduledMessage,
    workspaceId: 'ws1',
    launchProfileId: AutomationTabScope.simpleLaunchProfileId,
    sessionId: 'sess-1',
    message: 'ping',
    preset: AutomationSchedulePreset.daily,
    hourMinute: '09:00',
    timezone: 'UTC',
    dtstartMs: 1_700_000_000_000,
    enabled: enabled,
    nextRunAtMs: nextRunAtMs,
    createdAtMs: 1,
    updatedAtMs: 1,
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('save updates cubit list with computed nextRunAtMs', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    final calculator = AutomationScheduleCalculator();
    final dispatcher = AutomationDispatcher(
      repository: repo,
      scheduleCalculator: calculator,
      sessionRepository: _FakeSessionRepository(),
      busGateway: _NoopBusGateway(),
      requestOpenSession: (_) async => SessionOpenStatus.opened,
      requestCreateAndOpenSession: (_) async => SessionOpenStatus.opened,
      workspaceById: (_) => Workspace(workspaceId: 'ws1', createdAt: 1),
      teamById: (_) => null,
      launchProfileKindById: testLaunchProfileKindResolver(),
      nowMs: () => 1_700_000_000_000,
    );
    final scheduler = AutomationScheduler(
      repository: repo,
      dispatcher: dispatcher,
      scheduleCalculator: calculator,
      nowMs: () => 1_700_000_000_000,
    );
    final cubit = AutomationCubit(
      repository: repo,
      scheduler: scheduler,
      scheduleCalculator: calculator,
      nowMs: () => 1_700_000_000_000,
    );
    addTearDown(cubit.close);

    await cubit.load();
    await cubit.save(_sampleAutomation(id: 'a1'));

    expect(cubit.state.status, AutomationLoadStatus.ready);
    expect(cubit.state.automations, hasLength(1));
    expect(cubit.state.automations.single.nextRunAtMs, isNotNull);
  });

  test('toggleEnabled flips enabled and nextRunAtMs', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    final calculator = AutomationScheduleCalculator();
    final dispatcher = AutomationDispatcher(
      repository: repo,
      scheduleCalculator: calculator,
      sessionRepository: _FakeSessionRepository(),
      busGateway: _NoopBusGateway(),
      requestOpenSession: (_) async => SessionOpenStatus.opened,
      requestCreateAndOpenSession: (_) async => SessionOpenStatus.opened,
      workspaceById: (_) => Workspace(workspaceId: 'ws1', createdAt: 1),
      teamById: (_) => null,
      launchProfileKindById: testLaunchProfileKindResolver(),
      nowMs: () => 1_700_000_000_000,
    );
    final scheduler = AutomationScheduler(
      repository: repo,
      dispatcher: dispatcher,
      scheduleCalculator: calculator,
      nowMs: () => 1_700_000_000_000,
    );
    final cubit = AutomationCubit(
      repository: repo,
      scheduler: scheduler,
      scheduleCalculator: calculator,
      nowMs: () => 1_700_000_000_000,
    );
    addTearDown(cubit.close);

    await repo.upsert(
      _sampleAutomation(id: 'a1', enabled: true, nextRunAtMs: 123),
    );
    await cubit.loadForTabScope(simpleAutomationTabScope);
    await cubit.toggleEnabled(simpleAutomationTabScope, 'a1');

    final item = cubit.state.automations.single;
    expect(item.enabled, isFalse);
    expect(item.nextRunAtMs, isNull);

    await cubit.toggleEnabled(simpleAutomationTabScope, 'a1');
    final reenabled = cubit.state.automations.single;
    expect(reenabled.enabled, isTrue);
    expect(reenabled.nextRunAtMs, isNotNull);
  });

  test('loadForWorkspace keeps automations from every launch profile', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    final calculator = AutomationScheduleCalculator();
    final dispatcher = AutomationDispatcher(
      repository: repo,
      scheduleCalculator: calculator,
      sessionRepository: _FakeSessionRepository(),
      busGateway: _NoopBusGateway(),
      requestOpenSession: (_) async => SessionOpenStatus.opened,
      requestCreateAndOpenSession: (_) async => SessionOpenStatus.opened,
      workspaceById: (_) => Workspace(workspaceId: 'ws1', createdAt: 1),
      teamById: (_) => null,
      launchProfileKindById: testLaunchProfileKindResolver(),
      nowMs: () => 1_700_000_000_000,
    );
    final scheduler = AutomationScheduler(
      repository: repo,
      dispatcher: dispatcher,
      scheduleCalculator: calculator,
      nowMs: () => 1_700_000_000_000,
    );
    final cubit = AutomationCubit(
      repository: repo,
      scheduler: scheduler,
      scheduleCalculator: calculator,
      nowMs: () => 1_700_000_000_000,
    );
    addTearDown(cubit.close);

    await repo.upsert(_sampleAutomation(id: 'personal'));
    await repo.upsert(
      _sampleAutomation(id: 'team').copyWith(
        launchProfileId: 'team-1',
        action: AutomationAction.launchPrompt,
        clearSessionId: true,
        clearCli: true,
      ),
    );
    await cubit.loadForWorkspace('ws1');

    expect(cubit.state.listScope?.isWorkspace, isTrue);
    expect(cubit.state.visibleAutomations.map((a) => a.id), containsAll([
      'personal',
      'team',
    ]));
  });
}
