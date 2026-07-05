import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/repositories/automation_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../support/automation_test_fixtures.dart';
import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('listForWorkspace aggregates every launch profile in workspace', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    await repo.upsert(sampleAutomation(id: 'personal', workspaceId: 'ws1'));
    await repo.upsert(
      sampleAutomation(
        id: 'team',
        workspaceId: 'ws1',
        launchProfileId: 'team-1',
      ),
    );
    await repo.upsert(sampleAutomation(id: 'other', workspaceId: 'ws2'));

    final loaded = await repo.listForWorkspace('ws1');
    expect(loaded.map((a) => a.id), containsAll(['personal', 'team']));
    expect(loaded.map((a) => a.id), isNot(contains('other')));
  });

  test('upsert and listForTabScope round-trip', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    final automation = sampleAutomation(id: 'a1', workspaceId: 'ws1');
    await repo.upsert(automation);
    final loaded = await repo.listForTabScope(personalAutomationTabScope);
    expect(loaded, hasLength(1));
    expect(loaded.first.id, 'a1');
    expect(
      loaded.first.launchProfileId,
      personalAutomationTabScope.launchProfileId,
    );
  });

  test('catalog updated on upsert and listAll aggregates tab scopes', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    await repo.upsert(sampleAutomation(id: 'a1', workspaceId: 'ws1'));
    await repo.upsert(
      sampleAutomation(id: 'a2', workspaceId: 'ws2', launchProfileId: 'team-1'),
    );
    final all = await repo.listAll();
    expect(all.map((a) => a.id), containsAll(['a1', 'a2']));
  });

  test('upsertRun replaces run with same id', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    await repo.upsert(sampleAutomation(id: 'a1', workspaceId: 'ws1'));
    const runId = 'run-1';
    await repo.upsertRun(
      personalAutomationTabScope,
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
      personalAutomationTabScope,
      AutomationRun(
        id: runId,
        automationId: 'a1',
        workspaceId: 'ws1',
        scheduledForMs: 1,
        status: AutomationRunStatus.completed,
        trigger: AutomationRunTrigger.scheduled,
      ),
    );
    final runs = await repo.runsFor(
      personalAutomationTabScope,
      automationId: 'a1',
    );
    expect(runs, hasLength(1));
    expect(runs.single.status, AutomationRunStatus.completed);
  });

  test('appendRun truncates to maxRunsPerTabScope', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(
      fs: AppStorage.fs,
      layout: layout,
      maxRunsPerTabScope: 2,
    );
    await repo.upsert(sampleAutomation(id: 'a1', workspaceId: 'ws1'));
    for (var i = 0; i < 3; i++) {
      await repo.appendRun(
        personalAutomationTabScope,
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
    final runs = await repo.runsFor(personalAutomationTabScope);
    expect(runs, hasLength(2));
    expect(runs.map((r) => r.id), ['r1', 'r2']);
  });

  test(
    'disableForSession disables matching automations in tab scope',
    () async {
      final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
      final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
      await repo.upsert(
        sampleAutomation(
          id: 'a1',
          workspaceId: 'ws1',
          sessionId: 's1',
        ).copyWith(nextRunAtMs: 9_000),
      );
      await repo.disableForSession(personalAutomationTabScope, 's1');
      final loaded = await repo.listForTabScope(personalAutomationTabScope);
      expect(loaded.single.enabled, isFalse);
      expect(loaded.single.nextRunAtMs, isNull);
    },
  );

  test('disableForSession unbinds reusable launch prompts', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    await repo.upsert(
      sampleAutomation(id: 'a1', workspaceId: 'ws1').copyWith(
        action: AutomationAction.launchPrompt,
        sessionId: 's1',
        reuseSession: true,
        enabled: true,
        nextRunAtMs: 9_000,
      ),
    );
    await repo.disableForSession(personalAutomationTabScope, 's1');
    final loaded = await repo.listForTabScope(personalAutomationTabScope);
    expect(loaded.single.enabled, isTrue);
    expect(loaded.single.sessionId, isNull);
    expect(loaded.single.nextRunAtMs, 9_000);
  });

  test('removeWorkspace drops catalog entries and tab scope stores', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    await repo.upsert(sampleAutomation(id: 'a1', workspaceId: 'ws1'));
    expect(await repo.listAll(), hasLength(1));
    await repo.removeWorkspace('ws1');
    expect(await repo.listAll(), isEmpty);
    expect(await repo.listForTabScope(personalAutomationTabScope), isEmpty);
  });
}
