import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_identity.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_launch_project_dialog.dart';
import 'package:teampilot/pages/home_workspace/launch_project_team_order.dart';

void main() {
  test('open-with flow composes ordering + dialog choice into a route', () {
    final order = orderTeamIdsByRecentUse(
      projectId: 'p1',
      teamIds: const ['a'],
      sessions: const [],
    );
    expect(order, ['a']);
    const choice = LaunchProjectChoice(
      identity: LaunchIdentity.team('a'),
      remember: true,
    );
    final route = '/home-v2/project/p1?as=${choice.identity.encode()}';
    expect(route, '/home-v2/project/p1?as=team:a');
  });
}
