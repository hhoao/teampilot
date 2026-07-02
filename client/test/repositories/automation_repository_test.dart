import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/repositories/automation_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../support/post_frame_test_harness.dart';

Automation _sampleAutomation({
  required String id,
  required String workspaceId,
  String? sessionId,
}) {
  return Automation(
    id: id,
    name: 'Ping $id',
    action: AutomationAction.sendToLead,
    scope: sessionId == null ? AutomationScope.workspace : AutomationScope.session,
    workspaceId: workspaceId,
    sessionId: sessionId,
    message: 'hello',
    preset: AutomationSchedulePreset.daily,
    hourMinute: '09:00',
    timezone: 'UTC',
    dtstartMs: 1,
    enabled: true,
    createdAtMs: 1,
    updatedAtMs: 1,
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('upsert and listForWorkspace round-trip', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    final automation = _sampleAutomation(id: 'a1', workspaceId: 'ws1');
    await repo.upsert(automation);
    final loaded = await repo.listForWorkspace('ws1');
    expect(loaded, hasLength(1));
    expect(loaded.first.id, 'a1');
  });

  test('catalog updated on upsert and listAll aggregates workspaces', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    await repo.upsert(_sampleAutomation(id: 'a1', workspaceId: 'ws1'));
    await repo.upsert(_sampleAutomation(id: 'a2', workspaceId: 'ws2'));
    final all = await repo.listAll();
    expect(all.map((a) => a.id), containsAll(['a1', 'a2']));
  });

  test('upsertRun replaces run with same id', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    await repo.upsert(_sampleAutomation(id: 'a1', workspaceId: 'ws1'));
    const runId = 'run-1';
    await repo.upsertRun(
      'ws1',
      AutomationRun(
        id: runId,
        automationId: 'a1',
        workspaceId: 'ws1',
        scheduledForMs: 1,
        status: AutomationRunStatus.dispatching,
        trigger: AutomationRunTrigger.scheduled,
      ),
    );
    await repo.upsertRun(
      'ws1',
      AutomationRun(
        id: runId,
        automationId: 'a1',
        workspaceId: 'ws1',
        scheduledForMs: 1,
        status: AutomationRunStatus.completed,
        trigger: AutomationRunTrigger.scheduled,
      ),
    );
    final runs = await repo.runsFor('ws1', automationId: 'a1');
    expect(runs, hasLength(1));
    expect(runs.single.status, AutomationRunStatus.completed);
  });

  test('appendRun truncates to maxRunsPerWorkspace', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(
      fs: AppStorage.fs,
      layout: layout,
      maxRunsPerWorkspace: 2,
    );
    await repo.upsert(_sampleAutomation(id: 'a1', workspaceId: 'ws1'));
    for (var i = 0; i < 3; i++) {
      await repo.appendRun(
        'ws1',
        AutomationRun(
          id: 'r$i',
          automationId: 'a1',
          workspaceId: 'ws1',
          scheduledForMs: i,
          status: AutomationRunStatus.completed,
          trigger: AutomationRunTrigger.scheduled,
        ),
      );
    }
    final runs = await repo.runsFor('ws1');
    expect(runs, hasLength(2));
    expect(runs.map((r) => r.id), ['r1', 'r2']);
  });

  test('disableForSession disables matching automations', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    await repo.upsert(
      _sampleAutomation(id: 'a1', workspaceId: 'ws1', sessionId: 's1').copyWith(
        nextRunAtMs: 9_000,
      ),
    );
    await repo.disableForSession('ws1', 's1');
    final loaded = await repo.listForWorkspace('ws1');
    expect(loaded.single.enabled, isFalse);
    expect(loaded.single.nextRunAtMs, isNull);
  });

  test('removeWorkspace drops catalog entry and store file', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    await repo.upsert(_sampleAutomation(id: 'a1', workspaceId: 'ws1'));
    expect(await repo.listAll(), hasLength(1));
    await repo.removeWorkspace('ws1');
    expect(await repo.listAll(), isEmpty);
    expect(await repo.listForWorkspace('ws1'), isEmpty);
  });
}
