@Tags(['integration', 'cross-platform'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';

import 'support/team_bus_comm_task_harness.dart';
import 'support/teammate_bus_http_client.dart';

void main() {
  group('mixed team bus communication + tasks (HTTP MCP)', () {
    late TeamBusCommTaskHarness harness;

    tearDown(() async {
      await harness.dispose();
    });

    test('three-hop mail: lead → backend → frontend → lead', () async {
      harness = await TeamBusCommTaskHarness.create();
      final lead = harness.clientFor('team-lead');
      final backend = harness.clientFor('backend-dev');
      final frontend = harness.clientFor('frontend-dev');

      final backendWait = backend.waitForMessage();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await lead.sendMessage(to: 'backend-dev', content: 'plan the API');
      final planText = TeammateBusHttpClient.toolResultText(await backendWait);
      expect(planText, contains('plan the API'));

      final frontendWait = frontend.waitForMessage();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await backend.sendMessage(to: 'frontend-dev', content: 'wire the UI');
      expect(
        TeammateBusHttpClient.toolResultText(await frontendWait),
        contains('wire the UI'),
      );

      await frontend.sendMessage(to: 'team-lead', content: 'UI shipped');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final inbox = TeammateBusHttpClient.toolResultText(
        await lead.readMessages(unreadOnly: true),
      );
      expect(inbox, contains('UI shipped'));
    });

    test('broadcast reaches every non-lead teammate', () async {
      harness = await TeamBusCommTaskHarness.create();
      final lead = harness.clientFor('team-lead');
      final backendWait = harness.clientFor('backend-dev').waitForMessage();
      final frontendWait = harness.clientFor('frontend-dev').waitForMessage();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await lead.sendMessage(to: '*', content: 'standup in 5');

      expect(
        TeammateBusHttpClient.toolResultText(await backendWait),
        contains('standup in 5'),
      );
      expect(
        TeammateBusHttpClient.toolResultText(await frontendWait),
        contains('standup in 5'),
      );
    });

    test('parked worker auto-claims task from wait_for_message', () async {
      harness = await TeamBusCommTaskHarness.create();
      final lead = harness.clientFor('team-lead');
      final backend = harness.clientFor('backend-dev');

      final wait = backend.waitForMessage();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final enqueued = await lead.addTasks([
        <String, Object?>{
          'title': 'implement endpoint',
          'brief': 'POST /widgets',
          'required_capabilities': ['backend'],
        },
      ]);
      expect(TeammateBusHttpClient.toolSucceeded(enqueued), isTrue);

      final assigned = TeammateBusHttpClient.toolResultText(await wait);
      expect(assigned, contains('ASSIGNED TASK'));
      expect(assigned, contains('implement endpoint'));
      expect(assigned, contains('update_task'));

      expect(
        harness.bus.listTasks(status: TaskStatus.claimed).single.assignee,
        'backend-dev',
      );
    });

    test('claim_task rejects ineligible worker; eligible worker succeeds',
        () async {
      harness = await TeamBusCommTaskHarness.create();
      final lead = harness.clientFor('team-lead');
      final backend = harness.clientFor('backend-dev');
      final frontend = harness.clientFor('frontend-dev');

      final enqueued = await lead.addTasks([
        <String, Object?>{
          'title': 'db migration',
          'brief': 'add users table',
          'required_capabilities': ['backend'],
        },
      ]);
      final taskId = TeammateBusHttpClient.parseEnqueuedTasks(enqueued).single.id;

      expect(
        TeammateBusHttpClient.toolFailed(await frontend.claimTask(taskId)),
        isTrue,
      );
      final claimed = await backend.claimTask(taskId);
      expect(TeammateBusHttpClient.toolSucceeded(claimed), isTrue);
      expect(
        TeammateBusHttpClient.toolResultText(claimed),
        contains('db migration'),
      );
      expect(
        harness.bus.listTasks(status: TaskStatus.claimed).single.assignee,
        'backend-dev',
      );
    });

    test('preferred assignee reserves task until the named worker claims', () async {
      harness = await TeamBusCommTaskHarness.create();
      final lead = harness.clientFor('team-lead');
      final backend = harness.clientFor('backend-dev');
      final frontend = harness.clientFor('frontend-dev');

      final enqueued = await lead.addTasks([
        <String, Object?>{
          'title': 'hotfix',
          'brief': 'patch prod',
          'required_capabilities': ['backend'],
          'preferred_assignee': 'backend-dev',
        },
      ]);
      final taskId = TeammateBusHttpClient.parseEnqueuedTasks(enqueued).single.id;

      expect(
        TeammateBusHttpClient.toolFailed(await frontend.claimTask(taskId)),
        isTrue,
      );
      expect(
        TeammateBusHttpClient.toolSucceeded(await backend.claimTask(taskId)),
        isTrue,
      );
    });

    test('message beats queued task on wait_for_message', () async {
      harness = await TeamBusCommTaskHarness.create();
      final lead = harness.clientFor('team-lead');
      final backend = harness.clientFor('backend-dev');

      await lead.addTasks([
        <String, Object?>{
          'title': 'orphan task',
          'brief': 'should stay pending until mail is consumed',
        },
      ]);
      await lead.sendMessage(to: 'backend-dev', content: 'urgent: pause work');

      final first = TeammateBusHttpClient.toolResultText(
        await backend.waitForMessage(),
      );
      expect(first, contains('urgent'));
      expect(first, isNot(contains('ASSIGNED TASK')));

      expect(
        harness.bus.listTasks(status: TaskStatus.pending).single.title,
        'orphan task',
      );

      final second = TeammateBusHttpClient.toolResultText(
        await backend.waitForMessage(),
      );
      expect(second, contains('ASSIGNED TASK'));
      expect(second, contains('orphan task'));
    });

    test('dependency DAG: child blocked until parent marked done', () async {
      harness = await TeamBusCommTaskHarness.create();
      final lead = harness.clientFor('team-lead');
      final backend = harness.clientFor('backend-dev');

      final foundation = TeammateBusHttpClient.parseEnqueuedTasks(
        await lead.addTasks([
          <String, Object?>{
            'title': 'foundation',
            'brief': 'scaffold service',
            'required_capabilities': ['backend'],
          },
        ]),
      ).single;

      final featureEnqueued = await lead.addTasks([
        <String, Object?>{
          'title': 'feature',
          'brief': 'add widgets endpoint',
          'required_capabilities': ['backend'],
          'depends_on': [foundation.id],
        },
      ]);
      final featureId =
          TeammateBusHttpClient.parseEnqueuedTasks(featureEnqueued).single.id;

      expect(harness.bus.claimNextTask('backend-dev')!.title, 'foundation');
      expect(harness.bus.claimNextTask('backend-dev'), isNull);

      expect(
        TeammateBusHttpClient.toolSucceeded(
          await backend.updateTask(
            taskId: foundation.id,
            status: 'done',
            result: 'scaffold ready',
          ),
        ),
        isTrue,
      );

      final claimed = harness.bus.claimNextTask('backend-dev');
      expect(claimed!.id, featureId);
      expect(claimed.title, 'feature');

      expect(
        TeammateBusHttpClient.toolSucceeded(
          await backend.updateTask(taskId: featureId, status: 'done'),
        ),
        isTrue,
      );
      expect(harness.bus.listTasks(status: TaskStatus.done), hasLength(2));
    });

    test('end-to-end: enqueue → wait claim → done unlocks dependent', () async {
      harness = await TeamBusCommTaskHarness.create();
      final lead = harness.clientFor('team-lead');
      final backend = harness.clientFor('backend-dev');

      final setup = TeammateBusHttpClient.parseEnqueuedTasks(
        await lead.addTasks([
          <String, Object?>{
            'title': 'setup',
            'brief': 'create repo layout',
          },
        ]),
      ).single;

      final rolloutEnqueued = await lead.addTasks([
        <String, Object?>{
          'title': 'rollout',
          'brief': 'ship to staging',
          'depends_on': [setup.id],
        },
      ]);
      final rolloutId =
          TeammateBusHttpClient.parseEnqueuedTasks(rolloutEnqueued).single.id;

      final firstWait = backend.waitForMessage();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // Re-enqueue setup so the parked worker wakes (already pending).
      expect(harness.bus.listTasks(status: TaskStatus.pending), isNotEmpty);

      final firstAssigned = TeammateBusHttpClient.toolResultText(await firstWait);
      expect(firstAssigned, contains('setup'));

      final setupId = harness.bus.listTasks(status: TaskStatus.claimed).single.id;
      await backend.updateTask(taskId: setupId, status: 'done');

      final secondWait = backend.waitForMessage();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final secondAssigned =
          TeammateBusHttpClient.toolResultText(await secondWait);
      expect(secondAssigned, contains('rollout'));
      expect(
        harness.bus.listTasks(status: TaskStatus.claimed).single.id,
        rolloutId,
      );
    });

    test('two workers each auto-claim one task from the shared queue', () async {
      harness = await TeamBusCommTaskHarness.create(
        members: [
          (
            id: 'team-lead',
            isLead: true,
            capabilities: <String>{},
            lifecycle: MemberLifecycle.running,
            activity: MemberActivity.active,
          ),
          (
            id: 'worker-a',
            isLead: false,
            capabilities: <String>{},
            lifecycle: MemberLifecycle.running,
            activity: MemberActivity.turnDoneReady,
          ),
          (
            id: 'worker-b',
            isLead: false,
            capabilities: <String>{},
            lifecycle: MemberLifecycle.running,
            activity: MemberActivity.turnDoneReady,
          ),
        ],
      );
      final lead = harness.clientFor('team-lead');
      final waitA = harness.clientFor('worker-a').waitForMessage();
      final waitB = harness.clientFor('worker-b').waitForMessage();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await lead.addTasks([
        <String, Object?>{'title': 'task-1', 'brief': 'first'},
        <String, Object?>{'title': 'task-2', 'brief': 'second'},
      ]);

      final textA = TeammateBusHttpClient.toolResultText(await waitA);
      final textB = TeammateBusHttpClient.toolResultText(await waitB);
      expect(textA, contains('ASSIGNED TASK'));
      expect(textB, contains('ASSIGNED TASK'));
      expect(textA == textB, isFalse);

      final claimed = harness.bus.listTasks(status: TaskStatus.claimed);
      expect(claimed, hasLength(2));
      expect(claimed.map((t) => t.assignee).toSet(), {'worker-a', 'worker-b'});
    });

    test('idle worker notifies lead while parked in wait_for_message', () async {
      harness = await TeamBusCommTaskHarness.create();
      final backend = harness.clientFor('backend-dev');
      final lead = harness.clientFor('team-lead');

      final wait = backend.waitForMessage();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final inbox = TeammateBusHttpClient.toolResultText(
        await lead.readMessages(unreadOnly: true),
      );
      expect(inbox, contains('IDLE NOTIFICATION'));
      expect(inbox, contains('backend-dev'));

      // Unblock the parked wait so tearDown can close the HTTP client cleanly.
      await harness.clientFor('team-lead').sendMessage(
        to: 'backend-dev',
        content: 'ping',
      );
      expect(
        TeammateBusHttpClient.toolResultText(await wait),
        contains('ping'),
      );
    });

    test('add_tasks doorbells idle-at-prompt capability-matched worker', () async {
      harness = await TeamBusCommTaskHarness.create();
      final lead = harness.clientFor('team-lead');

      await lead.addTasks([
        <String, Object?>{
          'title': 'api layer',
          'brief': 'build handlers',
          'required_capabilities': ['backend'],
        },
      ]);

      expect(
        harness.launcher.woken.map((w) => w.memberId),
        contains('backend-dev'),
      );
      expect(harness.launcher.materialized, isEmpty);
    });

    test('routing opens task when no capable member exists, then fe claims',
        () async {
      var now = 1_000_000;
      harness = await TeamBusCommTaskHarness.create(
        members: [
          (
            id: 'team-lead',
            isLead: true,
            capabilities: <String>{},
            lifecycle: MemberLifecycle.running,
            activity: MemberActivity.active,
          ),
          (
            id: 'frontend-dev',
            isLead: false,
            capabilities: {'frontend'},
            lifecycle: MemberLifecycle.running,
            activity: MemberActivity.turnDoneReady,
          ),
        ],
        clock: () => now,
      );
      final lead = harness.clientFor('team-lead');

      await lead.addTasks([
        <String, Object?>{
          'title': 'api',
          'brief': 'needs backend',
          'required_capabilities': ['backend'],
          'preferred_capabilities': ['database'],
        },
      ]);

      expect(harness.bus.claimNextTask('frontend-dev'), isNull);

      now += 130 * 1000;
      harness.bus.reconcileTasks();
      now += 310 * 1000;
      harness.bus.reconcileTasks();

      final claimed = harness.bus.claimNextTask('frontend-dev');
      expect(claimed!.title, 'api');
      expect(claimed.routing.stage, RoutingStage.open);
    });
  });
}
