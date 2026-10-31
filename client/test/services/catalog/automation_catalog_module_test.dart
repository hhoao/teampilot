import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/automation.dart';
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
      runNow: (workspace, id) async => dispatched.add('$workspace/$id'),
      sessionExists: (sessionId, ws) async =>
          ws == workspaceId && sessionId == 'sess-1',
      teamExists: (teamId) => teamId == 'team-1',
      presetExists: (presetId) => presetId == 'preset-1',
      nowMs: () => now,
      newId: () => 'auto-1',
      defaultTimezone: () => 'UTC',
    );
  });

  CatalogRequest request(Map<String, Object?> args, {String sessionId = 'sess-1'}) {
    return CatalogRequest(
      sessionId: sessionId,
      workspaceId: workspaceId,
      arguments: args,
      workFs: LocalFilesystem(),
      allowedRoots: const [],
    );
  }

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
    expect(result.data!['next_run_at_ms'], isNotNull);
    expect(result.message, contains('Created disabled'));

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
        isA<CatalogException>().having((e) => e.code, 'code', 'schedule_invalid'),
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
    final result = await module.handle(CatalogOp.list, request(const {}));
    final data = result.data!['automation']! as Map<String, Object?>;
    final items = data['items']! as List;
    expect(items, hasLength(1));
    expect((items.single as Map)['id'], 'auto-1');
    expect((items.single as Map)['summary'], 'Hourly at :05');
    expect((items.single as Map)['last_run'], isNull);
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
      throwsA(isA<CatalogException>().having((e) => e.code, 'code', 'not_found')),
    );
  });
}
