import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/tasks/task_router.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';

TeamTask task({
  Set<String> required = const {},
  Set<String> preferred = const {},
  String? assignee,
  RoutingStage stage = RoutingStage.matched,
  int escalatedAt = 0,
}) {
  return TeamTask(
    id: 't', seq: 0, title: 'a', brief: 'b', createdBy: 'lead', createdAt: 0,
    requiredCapabilities: required,
    preferredCapabilities: preferred,
    preferredAssignee: assignee,
    routing: RoutingPolicy(stage: stage, escalatedAt: escalatedAt),
  );
}

void main() {
  group('eligible', () {
    test('empty requirements ⇒ anyone eligible at matched', () {
      expect(TaskRouter.eligible('w1', const {}, task()), isTrue);
    });

    test('subset match required at matched stage', () {
      final t = task(required: {'backend'});
      expect(TaskRouter.eligible('w1', {'backend', 'rust'}, t), isTrue);
      expect(TaskRouter.eligible('w2', {'frontend'}, t), isFalse);
    });

    test('reserved stage admits only the preferred assignee', () {
      final t = task(required: {'backend'}, assignee: 'dev2',
          stage: RoutingStage.reserved);
      expect(TaskRouter.eligible('dev2', {'backend'}, t), isTrue);
      expect(TaskRouter.eligible('other', {'backend'}, t), isFalse);
    });

    test('widened stage relaxes required to preferred', () {
      final t = task(required: {'backend'}, preferred: {'rust'},
          stage: RoutingStage.widened);
      // no longer needs backend; needs preferred (rust)
      expect(TaskRouter.eligible('w1', {'rust'}, t), isTrue);
      expect(TaskRouter.eligible('w2', {'go'}, t), isFalse);
    });

    test('open stage admits everyone', () {
      final t = task(required: {'backend'}, stage: RoutingStage.open);
      expect(TaskRouter.eligible('w1', const {}, t), isTrue);
    });
  });

  group('score', () {
    test('counts overlap with preferred capabilities', () {
      final t = task(preferred: {'rust', 'async', 'db'});
      expect(TaskRouter.score({'rust', 'db', 'frontend'}, t), 2);
      expect(TaskRouter.score(const {}, t), 0);
    });
  });

  group('nextStage', () {
    test('reserved → matched after reserve window', () {
      final t = task(assignee: 'd', stage: RoutingStage.reserved, escalatedAt: 0);
      expect(TaskRouter.nextStage(t, 44 * 1000, true), RoutingStage.reserved);
      expect(TaskRouter.nextStage(t, 45 * 1000, true), RoutingStage.matched);
    });

    test('matched stays while an eligible live member exists', () {
      final t = task(required: {'backend'}, escalatedAt: 0);
      expect(TaskRouter.nextStage(t, 999 * 1000, true), RoutingStage.matched);
    });

    test('matched → widened after widen window with no eligible live member', () {
      final t = task(required: {'backend'}, escalatedAt: 0);
      expect(TaskRouter.nextStage(t, 119 * 1000, false), RoutingStage.matched);
      expect(TaskRouter.nextStage(t, 120 * 1000, false), RoutingStage.widened);
    });

    test('widened → open after open window with no eligible live member', () {
      final t = task(stage: RoutingStage.widened, escalatedAt: 0);
      expect(TaskRouter.nextStage(t, 299 * 1000, false), RoutingStage.widened);
      expect(TaskRouter.nextStage(t, 300 * 1000, false), RoutingStage.open);
    });

    test('open is terminal', () {
      final t = task(stage: RoutingStage.open, escalatedAt: 0);
      expect(TaskRouter.nextStage(t, 999 * 1000, false), RoutingStage.open);
    });
  });
}
