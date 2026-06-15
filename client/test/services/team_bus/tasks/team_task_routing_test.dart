import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';

void main() {
  test('task defaults: no caps, matched stage, no preferred assignee', () {
    const t = TeamTask(
      id: 't0',
      seq: 0,
      title: 'a',
      brief: 'b',
      createdBy: 'lead',
      createdAt: 0,
    );
    expect(t.requiredCapabilities, isEmpty);
    expect(t.preferredCapabilities, isEmpty);
    expect(t.preferredAssignee, isNull);
    expect(t.routing.stage, RoutingStage.matched);
  });

  test('copyWith replaces the routing policy', () {
    const t = TeamTask(
      id: 't0', seq: 0, title: 'a', brief: 'b', createdBy: 'lead', createdAt: 0,
    );
    final r = t.copyWith(
      routing: t.routing.copyWith(stage: RoutingStage.open, escalatedAt: 5),
    );
    expect(r.routing.stage, RoutingStage.open);
    expect(r.routing.escalatedAt, 5);
    expect(t.routing.stage, RoutingStage.matched); // original unchanged
  });

  test('draft carries routing inputs', () {
    const d = TeamTaskDraft(
      title: 'a',
      brief: 'b',
      requiredCapabilities: {'backend'},
      preferredCapabilities: {'rust'},
      preferredAssignee: 'dev2',
    );
    expect(d.requiredCapabilities, {'backend'});
    expect(d.preferredCapabilities, {'rust'});
    expect(d.preferredAssignee, 'dev2');
  });
}
