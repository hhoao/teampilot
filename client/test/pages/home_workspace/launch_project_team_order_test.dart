import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/pages/home_workspace/launch_workspace_team_order.dart';

AppSession _s(String team, int updatedAt) => AppSession(
      sessionId: 's-$team-$updatedAt',
      workspaceId: 'p1',
      primaryPath: '/tmp/p1',
      sessionTeam: team,
      createdAt: 0,
      updatedAt: updatedAt,
    );

void main() {
  test('sorts team ids by most recent session for the workspace', () {
    final order = orderTeamIdsByRecentUse(
      workspaceId: 'p1',
      teamIds: const ['a', 'b', 'c'],
      sessions: [_s('b', 10), _s('a', 30), _s('b', 5)],
    );
    // a (30) > b (10) > c (none, keeps relative position last)
    expect(order, ['a', 'b', 'c']);
  });

  test('teams without sessions keep input order after used ones', () {
    final order = orderTeamIdsByRecentUse(
      workspaceId: 'p1',
      teamIds: const ['x', 'y', 'z'],
      sessions: [_s('z', 100)],
    );
    expect(order, ['z', 'x', 'y']);
  });
}
