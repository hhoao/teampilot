import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
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
