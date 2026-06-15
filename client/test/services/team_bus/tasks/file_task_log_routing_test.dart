import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/tasks/file_task_log.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('add persists caps + routing; escalate replays the stage', () async {
    final fs = InMemoryFilesystem();
    final log = FileTaskLog(queueRoot: '/q', fs: fs);

    await log.appendAdd(const TeamTask(
      id: 't0', seq: 0, title: 'a', brief: 'b', createdBy: 'lead', createdAt: 1,
      requiredCapabilities: {'backend'},
      preferredCapabilities: {'rust'},
      preferredAssignee: 'dev2',
      routing: RoutingPolicy(stage: RoutingStage.reserved, escalatedAt: 1),
    ));
    await log.appendEscalate('t0', RoutingStage.open, 99);

    final loaded = await log.load();
    final t = loaded.single;
    expect(t.requiredCapabilities, {'backend'});
    expect(t.preferredCapabilities, {'rust'});
    expect(t.preferredAssignee, 'dev2');
    expect(t.routing.stage, RoutingStage.open);
    expect(t.routing.escalatedAt, 99);
  });
}
