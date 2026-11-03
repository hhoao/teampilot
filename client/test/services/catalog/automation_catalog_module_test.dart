import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/automation_repository.dart';
import 'package:teampilot/services/automation/automation_schedule_calculator.dart';
import 'package:teampilot/services/catalog/catalog_kind.dart';
import 'package:teampilot/services/catalog/catalog_mutation_bus.dart';
import 'package:teampilot/services/catalog/modules/automation_catalog_module.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  const workspaceId = 'ws1';
  final now = DateTime.utc(2026, 10, 31, 8).millisecondsSinceEpoch;

  late AutomationRepository repo;
  late AutomationCatalogModule module;
  late List<String> dispatched;
  late List<CatalogMutationEvent> events;

  setUp(() {
    final layout = WorkspaceLayout(
      teampilotRoot: testHomeStorage.paths.basePath,
      fs: testHomeStorage.fs,
    );
    repo = AutomationRepository(fs: testHomeStorage.fs, layout: layout);
    dispatched = <String>[];
    events = <CatalogMutationEvent>[];
    final bus = CatalogMutationBus();
    bus.listen().listen(events.add);
    module = AutomationCatalogModule(
      repository: repo,
      scheduleCalculator: AutomationScheduleCalculator(),
      bus: bus,
      runNow: (workspace, id) async {
        dispatched.add('$workspace/$id');
        await repo.upsertRun(
          workspace,
          AutomationRun(
            id: 'run-new',
            automationId: id,
            workspaceId: workspace,
            scheduledForMs: now,
            status: AutomationRunStatus.completed,
            trigger: AutomationRunTrigger.manual,
            startedAtMs: now + 1000,
            completedAtMs: now + 1000,
          ),
        );
      },
      sessionExists: (sessionId, ws) async =>
          ws == workspaceId && sessionId == 'sess-1',
      teamExists: (teamId) => teamId == 'team-1',
      presetExists: (presetId) => presetId == 'preset-1',
      memberExists: (teamId, memberId) =>
          teamId == 'team-1' && memberId == 'team-lead',
      workspaceFolders: (_) => const [WorkspaceFolder(path: '/repo')],
      nowMs: () => now,
      newId: () => 'auto-1',
      defaultTimezone: () => 'UTC',
    );
  });

  CatalogRequest request(
    Map<String, Object?> args, {
    String sessionId = 'sess-1',
  }) {
    return CatalogRequest(
      sessionId: sessionId,
      workspaceId: workspaceId,
      arguments: args,
      workFs: LocalFilesystem(),
      allowedRoots: const [],
    );
  }

  CatalogRequest req(Map<String, Object?> args) => request(args);

  test('create forces disabled and returns the next run preview', () async {
    final result = await module.handle(
      CatalogOp.create,
      request({
        'name': 'Daily standup',
        'message': 'Summarize yesterday',
        'schedule': {'type': 'daily', 'time': '09:00'},
      }),
    );

    expect(result.ok, isTrue);
    expect(result.kind, 'automation');
    expect(result.restartRequired, isFalse);
    expect(result.ids, ['auto-1']);
    expect(result.data!['enabled'], isFalse);
    expect(
      result.data!['next_run_at_ms'],
      DateTime.utc(2026, 10, 31, 9).millisecondsSinceEpoch,
    );
    expect(result.message, contains('Created disabled'));

    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    expect(events.single.kind, 'automation');
    expect(events.single.op, CatalogOp.create);

    final stored = await repo.listForWorkspace(workspaceId);
    expect(stored, hasLength(1));
    expect(stored.single.enabled, isFalse);
    expect(stored.single.sessionId, 'sess-1');
    expect(stored.single.timezone, 'UTC');
  });

  test('create rejects an invalid cron', () async {
    await expectLater(
      module.handle(
        CatalogOp.create,
        request({
          'name': 'bad',
          'message': 'x',
          'schedule': {'type': 'custom', 'cron': 'not a cron'},
        }),
      ),
      throwsA(
        isA<CatalogException>().having(
          (e) => e.code,
          'code',
          'schedule_invalid',
        ),
      ),
    );
  });

  test('create launchPrompt requires a resolvable target', () async {
    await expectLater(
      module.handle(
        CatalogOp.create,
        request({
          'name': 'x',
          'message': 'x',
          'action': 'launchPrompt',
          'team_id': 'missing-team',
          'schedule': {'type': 'daily'},
        }),
      ),
      throwsA(
        isA<CatalogException>().having((e) => e.code, 'code', 'target_invalid'),
      ),
    );
  });

  test('create launchPrompt rejects an unknown team member', () async {
    await expectLater(
      module.handle(
        CatalogOp.create,
        request({
          'name': 'x',
          'message': 'x',
          'action': 'launchPrompt',
          'team_id': 'team-1',
          'target_member_id': 'ghost',
          'schedule': {'type': 'daily'},
        }),
      ),
      throwsA(
        isA<CatalogException>().having((e) => e.code, 'code', 'target_invalid'),
      ),
    );
  });

  test('create rejects a non-boolean reuse_session', () async {
    await expectLater(
      module.handle(
        CatalogOp.create,
        request({
          'name': 'x',
          'message': 'x',
          'action': 'launchPrompt',
          'team_id': 'team-1',
          'reuse_session': 1,
          'schedule': {'type': 'daily'},
        }),
      ),
      throwsA(
        isA<CatalogException>().having(
          (e) => e.code,
          'code',
          'invalid_argument',
        ),
      ),
    );
  });

  test('create launchPrompt stores team mode fields', () async {
    final result = await module.handle(
      CatalogOp.create,
      request({
        'name': 'team run',
        'message': 'go',
        'action': 'launchPrompt',
        'team_id': 'team-1',
        'schedule': {'type': 'weekly', 'time': '10:30', 'day_of_week': 3},
      }),
    );
    final stored = (await repo.listForWorkspace(workspaceId)).single;
    expect(result.ok, isTrue);
    expect(stored.isPersonal, isFalse);
    expect(stored.teamId, 'team-1');
    expect(stored.targetMemberId, 'team-lead');
    expect(stored.preset, AutomationSchedulePreset.weekly);
    expect(stored.dayOfWeek, 3);
    expect(stored.hourMinute, '10:30');
  });

  test('list groups automations and their latest run', () async {
    await module.handle(
      CatalogOp.create,
      request({
        'name': 'a',
        'message': 'm',
        'schedule': {'type': 'hourly', 'minute': 5},
      }),
    );
    await repo.upsertRun(
      workspaceId,
      AutomationRun(
        id: 'run-old',
        automationId: 'auto-1',
        workspaceId: workspaceId,
        scheduledForMs: 10,
        status: AutomationRunStatus.completed,
        trigger: AutomationRunTrigger.scheduled,
      ),
    );
    await repo.upsertRun(
      workspaceId,
      AutomationRun(
        id: 'run-new',
        automationId: 'auto-1',
        workspaceId: workspaceId,
        scheduledForMs: 20,
        status: AutomationRunStatus.dispatchFailed,
        trigger: AutomationRunTrigger.manual,
        startedAtMs: now - 1000,
      ),
    );

    final result = await module.handle(CatalogOp.list, request(const {}));
    final data = result.data!['automation']! as Map<String, Object?>;
    final items = data['items']! as List;
    expect(items, hasLength(1));
    final item = items.single as Map;
    expect(item['id'], 'auto-1');
    expect(item['summary'], 'Hourly at :05');
    expect((item['last_run']! as Map)['id'], 'run-new');
  });

  test('read without id behaves like list', () async {
    final result = await module.handle(CatalogOp.read, request(const {}));
    expect(result.data!.containsKey('automation'), isTrue);
  });

  test('read with a foreign workspace id is not_found', () async {
    final foreign = Automation(
      id: 'other',
      name: 'other',
      action: AutomationAction.scheduledMessage,
      workspaceId: 'ws2',
      sessionId: 'sess-2',
      message: 'x',
      preset: AutomationSchedulePreset.daily,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 1,
      enabled: false,
      createdAtMs: 1,
      updatedAtMs: 1,
    );
    await repo.upsert(foreign);
    await expectLater(
      module.handle(CatalogOp.read, request(const {'id': 'other'})),
      throwsA(
        isA<CatalogException>().having((e) => e.code, 'code', 'not_found'),
      ),
    );
  });

  test('create rejects a malformed time', () async {
    await expectLater(
      module.handle(
        CatalogOp.create,
        request({
          'name': 'x',
          'message': 'x',
          'schedule': {'type': 'daily', 'time': '9:0x'},
        }),
      ),
      throwsA(
        isA<CatalogException>().having(
          (e) => e.code,
          'code',
          'schedule_invalid',
        ),
      ),
    );
  });

  test('create rejects a stringly-typed minute', () async {
    await expectLater(
      module.handle(
        CatalogOp.create,
        request({
          'name': 'x',
          'message': 'x',
          'schedule': {'type': 'hourly', 'minute': '5'},
        }),
      ),
      throwsA(
        isA<CatalogException>().having(
          (e) => e.code,
          'code',
          'schedule_invalid',
        ),
      ),
    );
  });

  test('create persists the run limit and grace minutes', () async {
    await module.handle(
      CatalogOp.create,
      request({
        'name': 'limited',
        'message': 'x',
        'schedule': {'type': 'daily'},
        'max_run_count': 3,
        'missed_run_grace_minutes': 30,
      }),
    );
    final stored = (await repo.listForWorkspace(workspaceId)).single;
    expect(stored.effectiveMaxRunCount, 3);
    expect(stored.missedRunGraceMinutes, 30);
  });

  Future<String> createDaily({Map<String, Object?>? schedule}) async {
    final result = await module.handle(
      CatalogOp.create,
      request({
        'name': 'daily',
        'message': 'm',
        'schedule': schedule ?? {'type': 'daily', 'time': '09:00'},
      }),
    );
    return result.ids.single;
  }

  Future<void> seedForeign() async {
    await repo.upsert(
      Automation(
        id: 'other',
        name: 'other',
        action: AutomationAction.scheduledMessage,
        workspaceId: 'ws2',
        sessionId: 'sess-2',
        message: 'x',
        preset: AutomationSchedulePreset.daily,
        hourMinute: '09:00',
        timezone: 'UTC',
        dtstartMs: 1,
        enabled: false,
        createdAtMs: 1,
        updatedAtMs: 1,
      ),
    );
  }

  Future<void> flushEvents() => Future<void>.delayed(Duration.zero);

  test('update keeps unspecified fields and recomputes on enable', () async {
    final id = await createDaily();
    await module.handle(
      CatalogOp.update,
      request({'id': id, 'name': 'renamed', 'enabled': true}),
    );
    final stored = (await repo.listForWorkspace(workspaceId)).single;
    expect(stored.name, 'renamed');
    expect(stored.message, 'm');
    expect(stored.enabled, isTrue);
    expect(stored.nextRunAtMs, isNotNull);
  });

  test('update to disabled clears the next run', () async {
    final id = await createDaily();
    await module.handle(CatalogOp.update, request({'id': id, 'enabled': true}));
    await module.handle(
      CatalogOp.update,
      request({'id': id, 'enabled': false}),
    );
    final stored = (await repo.listForWorkspace(workspaceId)).single;
    expect(stored.enabled, isFalse);
    expect(stored.nextRunAtMs, isNull);
  });

  test('update rejects a non-boolean enabled and keeps storage', () async {
    final id = await createDaily();
    await expectLater(
      module.handle(CatalogOp.update, request({'id': id, 'enabled': 'true'})),
      throwsA(
        isA<CatalogException>().having(
          (e) => e.code,
          'code',
          'invalid_argument',
        ),
      ),
    );
    final stored = (await repo.listForWorkspace(workspaceId)).single;
    expect(stored.enabled, isFalse);
    expect(stored.nextRunAtMs, isNull);
  });

  test(
    'update rejects a non-boolean reuse_session and keeps storage',
    () async {
      final id = await createDaily();
      await expectLater(
        module.handle(
          CatalogOp.update,
          request({'id': id, 'reuse_session': 'yes'}),
        ),
        throwsA(
          isA<CatalogException>().having(
            (e) => e.code,
            'code',
            'invalid_argument',
          ),
        ),
      );
      final stored = (await repo.listForWorkspace(workspaceId)).single;
      expect(stored.reuseSession, isFalse);
    },
  );

  test('update enabling a past once schedule is schedule_invalid', () async {
    await repo.upsert(
      Automation(
        id: 'once-1',
        name: 'once',
        action: AutomationAction.scheduledMessage,
        workspaceId: workspaceId,
        sessionId: 'sess-1',
        message: 'x',
        preset: AutomationSchedulePreset.once,
        runAtMs: now - 1000,
        timezone: 'UTC',
        dtstartMs: 1,
        enabled: false,
        createdAtMs: 1,
        updatedAtMs: 1,
      ),
    );

    await expectLater(
      module.handle(
        CatalogOp.update,
        request({'id': 'once-1', 'enabled': true}),
      ),
      throwsA(
        isA<CatalogException>().having(
          (e) => e.code,
          'code',
          'schedule_invalid',
        ),
      ),
    );

    final stored = (await repo.listForWorkspace(workspaceId)).single;
    expect(stored.enabled, isFalse);
    expect(stored.nextRunAtMs, isNull);
    expect(dispatched, isEmpty);
  });

  test('update can switch a daily schedule to a cron schedule', () async {
    final id = await createDaily();
    await module.handle(
      CatalogOp.update,
      request({
        'id': id,
        'schedule': {'type': 'custom', 'cron': '*/15 * * * *'},
      }),
    );
    final stored = (await repo.listForWorkspace(workspaceId)).single;
    expect(stored.preset, AutomationSchedulePreset.custom);
    expect(stored.customCron, '*/15 * * * *');
    expect(stored.dayOfWeek, isNull);
    expect(stored.runAtMs, isNull);
    expect(stored.hourMinute, '09:00');
  });

  test(
    'update keeps timezone and dtstart when the schedule omits them',
    () async {
      final dtstart = now - 86400000;
      final id = await createDaily(
        schedule: {
          'type': 'daily',
          'time': '09:00',
          'timezone': 'Asia/Tokyo',
          'dtstart_ms': dtstart,
        },
      );
      await module.handle(
        CatalogOp.update,
        request({
          'id': id,
          'schedule': {'type': 'custom', 'cron': '*/15 * * * *'},
        }),
      );
      var stored = (await repo.listForWorkspace(workspaceId)).single;
      expect(stored.timezone, 'Asia/Tokyo');
      expect(stored.dtstartMs, dtstart);

      await module.handle(
        CatalogOp.update,
        request({
          'id': id,
          'schedule': {
            'type': 'custom',
            'cron': '*/15 * * * *',
            'timezone': 'UTC',
            'dtstart_ms': now,
          },
        }),
      );
      stored = (await repo.listForWorkspace(workspaceId)).single;
      expect(stored.timezone, 'UTC');
      expect(stored.dtstartMs, now);
    },
  );

  test('update of a foreign workspace id is not_found', () async {
    await seedForeign();
    await expectLater(
      module.handle(CatalogOp.update, request(const {'id': 'other'})),
      throwsA(
        isA<CatalogException>().having((e) => e.code, 'code', 'not_found'),
      ),
    );
  });

  test('delete of a foreign workspace id is not_found', () async {
    await seedForeign();
    await expectLater(
      module.handle(CatalogOp.delete, request(const {'id': 'other'})),
      throwsA(
        isA<CatalogException>().having((e) => e.code, 'code', 'not_found'),
      ),
    );
  });

  test('run_automation of a foreign workspace id is not_found', () async {
    await seedForeign();
    await expectLater(
      module.handle(CatalogOp.run, request(const {'id': 'other'})),
      throwsA(
        isA<CatalogException>().having((e) => e.code, 'code', 'not_found'),
      ),
    );
    expect(dispatched, isEmpty);
  });

  test('delete removes the automation and its runs', () async {
    final id = await createDaily();
    await repo.upsertRun(
      workspaceId,
      AutomationRun(
        id: 'run-1',
        automationId: id,
        workspaceId: workspaceId,
        scheduledForMs: now,
        status: AutomationRunStatus.completed,
        trigger: AutomationRunTrigger.manual,
        startedAtMs: now,
        completedAtMs: now,
      ),
    );
    await module.handle(CatalogOp.delete, request({'id': id}));
    expect(await repo.listForWorkspace(workspaceId), isEmpty);
    expect(await repo.runsForWorkspace(workspaceId), isEmpty);
  });

  test('run_automation dispatches and returns the newest run', () async {
    final id = await createDaily();
    await repo.upsertRun(
      workspaceId,
      AutomationRun(
        id: 'run-1',
        automationId: id,
        workspaceId: workspaceId,
        scheduledForMs: now,
        status: AutomationRunStatus.completed,
        trigger: AutomationRunTrigger.manual,
        startedAtMs: now,
        completedAtMs: now,
      ),
    );
    final result = await module.handle(CatalogOp.run, request({'id': id}));
    expect(dispatched, ['$workspaceId/$id']);
    expect((result.data!['run']! as Map)['id'], 'run-new');
  });

  test('run_automation rejects a run-limit-reached automation', () async {
    final id = await createDaily();
    final stored = (await repo.listForWorkspace(workspaceId)).single;
    await repo.upsert(
      stored.copyWith(
        preset: AutomationSchedulePreset.once,
        runAtMs: now + 60000,
        runCount: 1,
      ),
    );
    await expectLater(
      module.handle(CatalogOp.run, request({'id': id})),
      throwsA(
        isA<CatalogException>().having(
          (e) => e.code,
          'code',
          'run_limit_reached',
        ),
      ),
    );
  });

  test(
    'update cannot enable an automation that reached its run limit',
    () async {
      final id = await createDaily();
      final stored = (await repo.listForWorkspace(workspaceId)).single;
      await repo.upsert(stored.copyWith(maxRunCount: 1, runCount: 1));
      await expectLater(
        module.handle(CatalogOp.update, request({'id': id, 'enabled': true})),
        throwsA(
          isA<CatalogException>().having(
            (e) => e.code,
            'code',
            'run_limit_reached',
          ),
        ),
      );
      expect(dispatched, isEmpty);
      final after = (await repo.listForWorkspace(workspaceId)).single;
      expect(after.enabled, isFalse);
      expect(after.nextRunAtMs, isNull);
    },
  );

  test(
    'update translates a validate failure for an enabled automation',
    () async {
      final id = await createDaily();
      await module.handle(
        CatalogOp.update,
        request({'id': id, 'enabled': true}),
      );
      await expectLater(
        module.handle(
          CatalogOp.update,
          request({'id': id, 'reuse_session': true}),
        ),
        throwsA(
          isA<CatalogException>().having(
            (e) => e.code,
            'code',
            'invalid_argument',
          ),
        ),
      );
    },
  );

  test('update emits an automation bus event', () async {
    final id = await createDaily();
    await module.handle(
      CatalogOp.update,
      request({'id': id, 'name': 'renamed'}),
    );
    await flushEvents();
    expect(events.map((e) => e.op).toList(), [
      CatalogOp.create,
      CatalogOp.update,
    ]);
    expect(events.every((e) => e.kind == 'automation'), isTrue);
  });

  test('delete emits an automation bus event', () async {
    final id = await createDaily();
    await module.handle(CatalogOp.delete, request({'id': id}));
    await flushEvents();
    expect(events.map((e) => e.op).toList(), [
      CatalogOp.create,
      CatalogOp.delete,
    ]);
  });

  test('run_automation emits an automation bus event', () async {
    final id = await createDaily();
    await module.handle(CatalogOp.run, request({'id': id}));
    await flushEvents();
    expect(events.map((e) => e.op).toList(), [CatalogOp.create, CatalogOp.run]);
  });

  test('create runCommand defaults to disabled', () async {
    final result = await module.handle(
      CatalogOp.create,
      req({
        'name': 'nightly',
        'action': 'runCommand',
        'command': 'npm ci && npm run build',
        'schedule': {'type': 'daily', 'time': '02:00'},
      }),
    );
    final data = result.data!['automation']! as Map<String, Object?>;
    expect(data['enabled'], isFalse);
    expect(data['command'], 'npm ci && npm run build');
    expect(data['timeoutSeconds'], 300);
    expect(data['catchUpPolicy'], 'none');
  });

  test('create runCommand honours enabled true', () async {
    final result = await module.handle(
      CatalogOp.create,
      req({
        'name': 'nightly',
        'action': 'runCommand',
        'command': 'make',
        'enabled': true,
        'schedule': {'type': 'daily', 'time': '02:00'},
      }),
    );
    final data = result.data!['automation']! as Map<String, Object?>;
    expect(data['enabled'], isTrue);
    expect(data['nextRunAtMs'], isNotNull);
  });

  test('create runCommand rejects an empty command', () async {
    await expectLater(
      module.handle(
        CatalogOp.create,
        req({
          'name': 'nightly',
          'action': 'runCommand',
          'command': '   ',
          'schedule': {'type': 'daily', 'time': '02:00'},
        }),
      ),
      throwsA(
        isA<CatalogException>().having(
          (e) => e.code,
          'code',
          'command_invalid',
        ),
      ),
    );
  });

  test(
    'create runCommand rejects a working directory outside the workspace',
    () async {
      await expectLater(
        module.handle(
          CatalogOp.create,
          req({
            'name': 'nightly',
            'action': 'runCommand',
            'command': 'make',
            'working_directory': '/elsewhere',
            'schedule': {'type': 'daily', 'time': '02:00'},
          }),
        ),
        throwsA(
          isA<CatalogException>().having(
            (e) => e.code,
            'code',
            'working_directory_invalid',
          ),
        ),
      );
    },
  );

  test('update patches command and timeout', () async {
    final created = await module.handle(
      CatalogOp.create,
      req({
        'name': 'nightly',
        'action': 'runCommand',
        'command': 'make',
        'schedule': {'type': 'daily', 'time': '02:00'},
      }),
    );
    final id =
        (created.data!['automation']! as Map<String, Object?>)['id'] as String;

    final updated = await module.handle(
      CatalogOp.update,
      req({
        'id': id,
        'command': 'make release',
        'timeout_seconds': 900,
        'catch_up': 'once',
      }),
    );
    final data = updated.data!['automation']! as Map<String, Object?>;
    expect(data['command'], 'make release');
    expect(data['timeoutSeconds'], 900);
    expect(data['catchUpPolicy'], 'once');
  });

  test(
    'create runCommand persists working_directory to the repository',
    () async {
      await module.handle(
        CatalogOp.create,
        req({
          'name': 'nightly',
          'action': 'runCommand',
          'command': 'make',
          'working_directory': '/repo/sub',
          'schedule': {'type': 'daily', 'time': '02:00'},
        }),
      );

      final stored = await repo.listForWorkspace(workspaceId);
      final automation = stored.singleWhere((a) => a.name == 'nightly');
      expect(automation.workingDirectoryPath, '/repo/sub');
    },
  );
}
