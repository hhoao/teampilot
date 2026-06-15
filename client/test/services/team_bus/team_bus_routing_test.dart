import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/tasks/task_queue.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import 'support/fake_member_launcher.dart';

TeamBus _busWithQueue(FakeMemberLauncher launcher) =>
    TeamBus(launcher: launcher, taskQueue: TaskQueue());

AgentNode _declared(String id, Set<String> caps) =>
    AgentNode.test(memberId: id, capabilities: caps);

AgentNode _atPrompt(String id, Set<String> caps) => AgentNode.test(
      memberId: id,
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.turnDoneReady,
      capabilities: caps,
    );

void main() {
  test('engagement cold-starts the capability-matched declared worker', () {
    fakeAsync((async) {
      final launcher = FakeMemberLauncher();
      final bus = _busWithQueue(launcher);
      bus.declareMember(_declared('fe', {'frontend'}));
      bus.declareMember(_declared('be', {'backend'}));

      bus.addTasks('lead', [
        const TeamTaskDraft(title: 'api', brief: 'b',
            requiredCapabilities: {'backend'}),
      ]);
      async.flushMicrotasks();

      expect(launcher.materialized.single.memberId, 'be'); // not 'fe'
    });
  });

  test('engagement doorbells the capability-matched at-prompt worker', () {
    fakeAsync((async) {
      final launcher = FakeMemberLauncher();
      final bus = _busWithQueue(launcher);
      bus.declareMember(_atPrompt('fe', {'frontend'}));
      bus.declareMember(_atPrompt('be', {'backend'}));

      bus.addTasks('lead', [
        const TeamTaskDraft(title: 'api', brief: 'b',
            requiredCapabilities: {'backend'}),
      ]);
      async.flushMicrotasks();

      expect(launcher.woken.single.memberId, 'be');
      expect(launcher.materialized, isEmpty);
    });
  });

  test('reconcileTasks opens a task when no capable member exists', () {
    fakeAsync((async) {
      // Inject a controllable clock shared by the bus and its queue —
      // fakeAsync.elapse does not advance DateTime.now(), so routing windows
      // must be driven by a manual clock.
      var now = 1000;
      final bus = TeamBus(
        launcher: FakeMemberLauncher(),
        clock: () => now,
        taskQueue: TaskQueue(clock: () => now),
      );
      // Only a frontend worker exists; the task needs backend (required) and
      // database (preferred) — fe matches neither, so even the widened stage
      // (which relaxes to preferred) cannot match it, forcing escalation to open.
      bus.declareMember(_declared('fe', {'frontend'}));
      bus.addTasks('lead', [
        const TeamTaskDraft(title: 'api', brief: 'b',
            requiredCapabilities: {'backend'},
            preferredCapabilities: {'database'}),
      ]);
      async.flushMicrotasks();

      now += 130 * 1000; // past widen window
      bus.reconcileTasks();
      now += 310 * 1000; // past open window
      bus.reconcileTasks();

      expect(bus.listTasks(status: TaskStatus.pending).single.routing.stage,
          RoutingStage.open);
      // now the frontend worker can claim it as a fungible fallback
      final claimed = bus.claimNextTask('fe');
      expect(claimed!.title, 'api');

      bus.dispose();
    });
  });
}
