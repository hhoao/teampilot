import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/tasks/in_memory_task_log.dart';
import 'package:teampilot/services/team_bus/tasks/task_queue.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';

void main() {
  late int idSeq;
  late int now;

  TaskQueue makeQueue({InMemoryTaskLog? log}) {
    idSeq = 0;
    now = 1000;
    return TaskQueue(
      log: log,
      ids: () => 't${idSeq++}',
      clock: () => now,
    );
  }

  TeamTaskDraft draft(String title, {List<String> deps = const []}) =>
      TeamTaskDraft(title: title, brief: 'brief: $title', dependsOn: deps);

  test('addTasks assigns ids/seq and lists FIFO', () {
    final q = makeQueue();
    final created = q.addTasks('lead', [draft('a'), draft('b')]);

    expect(created.map((t) => t.id), ['t0', 't1']);
    expect(created.every((t) => t.status == TaskStatus.pending), isTrue);
    expect(q.list().map((t) => t.title), ['a', 'b']);
    expect(q.claimableCount, 2);
  });

  test('claimNext is FIFO and marks the task claimed by the worker', () {
    final q = makeQueue();
    q.addTasks('lead', [draft('a'), draft('b')]);

    final first = q.claimNext('w1');
    expect(first!.title, 'a');
    expect(first.status, TaskStatus.claimed);
    expect(first.assignee, 'w1');

    final second = q.claimNext('w2');
    expect(second!.title, 'b');
    expect(second.assignee, 'w2');

    expect(q.claimNext('w3'), isNull); // nothing left
  });

  test('two claimers never get the same task', () {
    final q = makeQueue();
    q.addTasks('lead', [draft('only')]);

    final a = q.claimNext('w1');
    final b = q.claimNext('w2');

    expect(a, isNotNull);
    expect(b, isNull);
  });

  test('dependencies gate claimability until the dep is done', () {
    final q = makeQueue();
    final created = q.addTasks('lead', [draft('root')]);
    final rootId = created.single.id;
    q.addTasks('lead', [draft('child', deps: [rootId])]);

    // child blocked: only root is claimable
    expect(q.claimableCount, 1);
    final root = q.claimNext('w1');
    expect(root!.title, 'root');
    expect(q.claimNext('w2'), isNull); // child still blocked (root not done)

    q.update(rootId, TaskStatus.done, byMember: 'w1');
    final child = q.claimNext('w2');
    expect(child!.title, 'child');
  });

  test('update rejects a non-claimer and accepts the claimer', () {
    final q = makeQueue();
    final id = q.addTasks('lead', [draft('a')]).single.id;
    q.claimNext('w1');

    expect(q.update(id, TaskStatus.done, byMember: 'intruder'), isFalse);
    expect(q.update(id, TaskStatus.done, byMember: 'w1', result: 'ok'), isTrue);
    expect(q.list(status: TaskStatus.done).single.result, 'ok');
  });

  test('reclaimExpired requeues a dead worker\'s task past the lease', () {
    final q = makeQueue();
    q.addTasks('lead', [draft('a')]);
    q.claimNext('w1');

    now += 60 * 1000; // 60s, under default-ish lease handled by arg below

    // still alive → not reclaimed
    var reclaimed = q.reclaimExpired(leaseMs: 30 * 1000, isAlive: (_) => true);
    expect(reclaimed, isEmpty);

    // dead → reclaimed back to pending
    reclaimed = q.reclaimExpired(leaseMs: 30 * 1000, isAlive: (_) => false);
    expect(reclaimed.single.status, TaskStatus.pending);
    expect(q.claimNext('w2'), isNotNull); // claimable again
  });

  test('rehydrate replays the log into a fresh queue', () async {
    final log = InMemoryTaskLog();
    final q1 = makeQueue(log: log);
    final ids = q1.addTasks('lead', [draft('a'), draft('b')]);
    q1.claimNext('w1'); // claim 'a'
    q1.update(ids.first.id, TaskStatus.done, byMember: 'w1', result: 'done-a');

    final q2 = makeQueue(log: log);
    await q2.rehydrate();

    final all = q2.list();
    expect(all.map((t) => t.title), ['a', 'b']);
    expect(all.firstWhere((t) => t.title == 'a').status, TaskStatus.done);
    expect(all.firstWhere((t) => t.title == 'b').status, TaskStatus.pending);
    // seq cursor continues past replayed tasks
    final more = q2.addTasks('lead', [draft('c')]);
    expect(more.single.seq, 2);
  });
}
