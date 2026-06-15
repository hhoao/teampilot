import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/tasks/task_queue.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';

void main() {
  late int idSeq;
  late int now;

  TaskQueue makeQueue() {
    idSeq = 0;
    now = 1000;
    return TaskQueue(ids: () => 't${idSeq++}', clock: () => now);
  }

  test('claimNext skips tasks the member is not eligible for', () {
    final q = makeQueue();
    q.addTasks('lead', [
      const TeamTaskDraft(title: 'fe', brief: 'b', requiredCapabilities: {'frontend'}),
      const TeamTaskDraft(title: 'be', brief: 'b', requiredCapabilities: {'backend'}),
    ]);

    final claimed = q.claimNext('w1', {'backend'});
    expect(claimed!.title, 'be'); // skips the frontend task at seq 0
    expect(q.claimNext('w1', {'backend'}), isNull); // nothing else eligible
  });

  test('claimNext orders eligible tasks by score then seq', () {
    final q = makeQueue();
    q.addTasks('lead', [
      const TeamTaskDraft(title: 'low', brief: 'b', preferredCapabilities: {'rust'}),
      const TeamTaskDraft(title: 'high', brief: 'b',
          preferredCapabilities: {'rust', 'async'}),
    ]);
    // worker has both preferred caps for 'high' (score 2) vs 'low' (score 1)
    final claimed = q.claimNext('w1', {'rust', 'async'});
    expect(claimed!.title, 'high');
  });

  test('reserved task is claimable only by the preferred assignee', () {
    final q = makeQueue();
    q.addTasks('lead', [
      const TeamTaskDraft(title: 'a', brief: 'b', preferredAssignee: 'dev2'),
    ]);
    expect(q.claimNext('other', const {}), isNull); // reserved for dev2
    expect(q.claimNext('dev2', const {})!.title, 'a');
  });

  test('claimSpecific enforces eligibility and atomicity', () {
    final q = makeQueue();
    final id = q
        .addTasks('lead', [
          const TeamTaskDraft(title: 'be', brief: 'b',
              requiredCapabilities: {'backend'})
        ])
        .single
        .id;

    expect(q.claimSpecific(id, 'w1', {'frontend'}), isNull); // ineligible
    final ok = q.claimSpecific(id, 'w2', {'backend'});
    expect(ok!.assignee, 'w2');
    expect(q.claimSpecific(id, 'w3', {'backend'}), isNull); // already claimed
  });

  test('reconcile escalates reserved → matched after the reserve window', () {
    final q = makeQueue();
    q.addTasks('lead', [
      const TeamTaskDraft(title: 'a', brief: 'b', preferredAssignee: 'dev2'),
    ]);
    expect(q.list().single.routing.stage, RoutingStage.reserved);

    now += 45 * 1000;
    final changed = q.reconcile(now, (_) => true);
    expect(changed.single.routing.stage, RoutingStage.matched);
    // now any worker can claim
    expect(q.claimNext('anyone', const {})!.title, 'a');
  });

  test('reconcile widens then opens when no eligible live member exists', () {
    final q = makeQueue();
    q.addTasks('lead', [
      const TeamTaskDraft(title: 'a', brief: 'b', requiredCapabilities: {'backend'}),
    ]);

    now += 120 * 1000;
    expect(q.reconcile(now, (_) => false).single.routing.stage,
        RoutingStage.widened);

    now += 300 * 1000;
    expect(q.reconcile(now, (_) => false).single.routing.stage,
        RoutingStage.open);
    expect(q.claimNext('anyone', const {})!.title, 'a'); // fungible fallback
  });
}
