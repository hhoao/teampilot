import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/idle_notification.dart';
import 'package:teampilot/services/team_bus/tasks/task_queue.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import 'support/fake_member_launcher.dart';

TeamBus _busWithQueue(FakeMemberLauncher launcher) =>
    TeamBus(launcher: launcher, taskQueue: TaskQueue());

AgentNode _runningWorker(String id) => AgentNode.test(
      memberId: id,
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    );

AgentNode _declaredWorker(String id) => AgentNode.test(memberId: id);

AgentNode _parkedWorker(String id) => AgentNode.test(
      memberId: id,
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.turnDoneBusWait,
    );

// Launched but never entered wait_for_message (no initial prompt kicked it off).
AgentNode _idleAtPromptWorker(String id) => AgentNode.test(
      memberId: id,
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.turnDoneReady,
    );

void main() {
  test('a bus without a task queue exposes no work-queue surface', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    expect(bus.hasTaskQueue, isFalse);
    expect(bus.addTasks('lead', [const TeamTaskDraft(title: 'a', brief: 'b')]),
        isEmpty);
    expect(bus.listTasks(), isEmpty);
  });

  test('add_tasks then update flows through the bus', () {
    final bus = _busWithQueue(FakeMemberLauncher());
    final created =
        bus.addTasks('lead', [const TeamTaskDraft(title: 'a', brief: 'do a')]);
    expect(created.single.title, 'a');

    final claimed = bus.claimNextTask('w1');
    expect(claimed!.assignee, 'w1');

    expect(bus.updateTask(claimed.id, TaskStatus.done, byMember: 'w1'), isTrue);
    expect(bus.listTasks(status: TaskStatus.done).single.id, claimed.id);
  });

  test('receiveWork auto-claims a queued task for a parked worker', () {
    fakeAsync((async) {
      final bus = _busWithQueue(FakeMemberLauncher());
      bus.declareMember(_runningWorker('w1'));

      WorkBatch? got;
      bus.receiveWork('w1').then((b) => got = b);
      async.flushMicrotasks();
      expect(got, isNull); // parked: no messages, no tasks

      // Enqueue — the parked worker should be woken and handed the task.
      bus.addTasks('lead', [const TeamTaskDraft(title: 'a', brief: 'do a')]);
      async.flushMicrotasks();

      expect(got, isA<TaskWork>());
      expect((got! as TaskWork).task.title, 'a');
      expect((got! as TaskWork).task.assignee, 'w1');
    });
  });

  test('receiveWork prefers pending messages over a queued task', () {
    fakeAsync((async) {
      final bus = _busWithQueue(FakeMemberLauncher());
      final worker = _runningWorker('w1');
      bus.declareMember(worker);

      // Both a message and a task are available; messages win.
      worker.inbox
          .deliver(TeamMessage(id: 'm1', from: 'lead', to: 'w1', content: 'hi'));
      bus.addTasks('lead', [const TeamTaskDraft(title: 'a', brief: 'do a')]);

      WorkBatch? got;
      bus.receiveWork('w1').then((b) => got = b);
      async.flushMicrotasks();

      expect(got, isA<MessageWork>());
      expect((got! as MessageWork).messages.single.content, 'hi');
      // task remains claimable for the next call
      expect(bus.listTasks(status: TaskStatus.pending).single.title, 'a');
    });
  });

  test('the team lead never auto-claims tasks', () {
    fakeAsync((async) {
      final bus = _busWithQueue(FakeMemberLauncher());
      bus.declareMember(AgentNode.test(
        memberId: 'lead',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
        isTeamLead: true,
      ));

      WorkBatch? got;
      bus.receiveWork('lead').then((b) => got = b);
      async.flushMicrotasks();

      bus.addTasks('lead', [const TeamTaskDraft(title: 'a', brief: 'do a')]);
      async.flushMicrotasks();

      expect(got, isNull); // lead stays parked; task untouched
      expect(bus.listTasks(status: TaskStatus.pending).single.title, 'a');
    });
  });

  test('add_tasks materializes a declared worker so it can come online', () {
    fakeAsync((async) {
      final launcher = FakeMemberLauncher();
      final bus = _busWithQueue(launcher);
      bus.declareMember(_declaredWorker('w1'));

      bus.addTasks('lead', [const TeamTaskDraft(title: 'a', brief: 'do a')]);
      async.flushMicrotasks();

      // Declared worker is brought online (PTY launch) so it can wait_for_message
      // and claim — without this, the task would sit unclaimed (the bug).
      expect(launcher.materialized.single.memberId, 'w1');
    });
  });

  test('add_tasks doorbells a running idle-at-prompt worker to claim', () {
    fakeAsync((async) {
      final launcher = FakeMemberLauncher();
      final bus = _busWithQueue(launcher);
      // Worker launched eagerly but never entered wait_for_message → stuck at
      // prompt. queue._wake can't reach it; only a doorbell kicks it to claim.
      bus.declareMember(_idleAtPromptWorker('w1'));

      bus.addTasks('lead', [const TeamTaskDraft(title: 'a', brief: 'do a')]);
      async.flushMicrotasks();

      expect(launcher.materialized, isEmpty); // already running, no cold start
      expect(launcher.woken.single.memberId, 'w1');
      expect(launcher.woken.single.notice, TeamBus.taskDoorbellNotice);
    });
  });

  test('add_tasks prefers doorbelling a running worker over cold-starting one', () {
    fakeAsync((async) {
      final launcher = FakeMemberLauncher();
      final bus = _busWithQueue(launcher);
      bus.declareMember(_idleAtPromptWorker('running'));
      bus.declareMember(_declaredWorker('cold'));

      // One task, two idle workers → engage the cheap running one, not cold start.
      bus.addTasks('lead', [const TeamTaskDraft(title: 'a', brief: 'do a')]);
      async.flushMicrotasks();

      expect(launcher.woken.single.memberId, 'running');
      expect(launcher.materialized, isEmpty);
    });
  });

  test('add_tasks never materializes the team lead', () {
    fakeAsync((async) {
      final launcher = FakeMemberLauncher();
      final bus = _busWithQueue(launcher);
      bus.declareMember(AgentNode.test(memberId: 'lead', isTeamLead: true));
      bus.declareMember(_declaredWorker('w1'));

      bus.addTasks('lead', [const TeamTaskDraft(title: 'a', brief: 'do a')]);
      async.flushMicrotasks();

      expect(launcher.materialized.map((m) => m.memberId), ['w1']);
    });
  });

  test('add_tasks caps materialization at the claimable task count', () {
    fakeAsync((async) {
      final launcher = FakeMemberLauncher();
      final bus = _busWithQueue(launcher);
      bus.declareMember(_declaredWorker('w1'));
      bus.declareMember(_declaredWorker('w2'));
      bus.declareMember(_declaredWorker('w3'));

      // One task → only one worker brought online; no over-provisioning.
      bus.addTasks('lead', [const TeamTaskDraft(title: 'a', brief: 'do a')]);
      async.flushMicrotasks();

      expect(launcher.materialized.length, 1);
    });
  });

  test('add_tasks skips materialization when a parked worker can claim', () {
    fakeAsync((async) {
      final launcher = FakeMemberLauncher();
      final bus = _busWithQueue(launcher);
      bus.declareMember(_parkedWorker('w1')); // already running, in wait_for_message
      bus.declareMember(_declaredWorker('w2'));

      // The parked worker is woken by the queue waiter and claims; the declared
      // worker needn't be launched (budget = claimable 1 − parked 1 = 0).
      bus.addTasks('lead', [const TeamTaskDraft(title: 'a', brief: 'do a')]);
      async.flushMicrotasks();

      expect(launcher.materialized, isEmpty);
    });
  });

  test('receiveWork notifies the lead when a worker goes idle with no work', () {
    fakeAsync((async) {
      final bus = _busWithQueue(FakeMemberLauncher());
      final lead = AgentNode.test(
        memberId: 'lead',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
        isTeamLead: true,
      );
      bus.declareMember(lead);
      bus.declareMember(_runningWorker('w1'));

      // Worker waits with nothing to do → blocks → announces idle to the lead
      // (the Claude Code "transition to idle → notify leader" moment).
      bus.receiveWork('w1');
      async.flushMicrotasks();

      expect(lead.inbox.isEmpty, isFalse);
      final note = IdleNotification.parseTeamMessageContent(
        lead.inbox.peekAll().single.content,
      );
      expect(note, isNotNull);
      expect(note!.from, 'w1');
      expect(note.idleReason, IdleReason.available);
    });
  });

  test('a worker that claims work does not announce idle', () {
    fakeAsync((async) {
      final bus = _busWithQueue(FakeMemberLauncher());
      final lead = AgentNode.test(
        memberId: 'lead',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
        isTeamLead: true,
      );
      bus.declareMember(lead);
      bus.declareMember(_runningWorker('w1'));
      bus.addTasks('lead', [const TeamTaskDraft(title: 'a', brief: 'do a')]);

      // Work is available → claims immediately, never blocks → no idle ping.
      WorkBatch? got;
      bus.receiveWork('w1').then((b) => got = b);
      async.flushMicrotasks();

      expect(got, isA<TaskWork>());
      expect(lead.inbox.isEmpty, isTrue);
    });
  });

  test('releaseTask returns a claimed task to pending', () {
    final bus = _busWithQueue(FakeMemberLauncher());
    final id = bus
        .addTasks('lead', [const TeamTaskDraft(title: 'a', brief: 'do a')])
        .single
        .id;
    final claimed = bus.claimNextTask('w1');
    expect(claimed!.status, TaskStatus.claimed);

    bus.releaseTask(id);
    expect(bus.listTasks(status: TaskStatus.pending).single.id, id);
  });
}
