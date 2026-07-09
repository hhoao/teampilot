import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_global_section.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_route.dart';

void main() {
  test('fromSegment resolves myTeams and myExperts', () {
    expect(HomeGlobalView.fromSegment('myTeams'), HomeGlobalView.myTeams);
    expect(HomeGlobalView.fromSegment('myExperts'), HomeGlobalView.myExperts);
  });

  test('home deep link parses global myTeams', () {
    expect(
      HomeWorkspaceRoute.homeGlobalView('/home-v2?global=myTeams'),
      HomeGlobalView.myTeams,
    );
  });

  test('myTeamsTeamId parses team query when global is myTeams', () {
    expect(
      HomeWorkspaceRoute.myTeamsTeamId('/home-v2?global=myTeams&team=abc'),
      'abc',
    );
  });

  test('myExpertsMemberKey parses member query when global is myExperts', () {
    expect(
      HomeWorkspaceRoute.myExpertsMemberKey(
        '/home-v2?global=myExperts&member=local/x',
      ),
      'local/x',
    );
  });

  test('myTeamsTeamId returns null for wrong global view', () {
    expect(
      HomeWorkspaceRoute.myTeamsTeamId('/home-v2?global=teamHub&team=abc'),
      isNull,
    );
  });

  test('myExpertsMemberKey returns null for wrong global view', () {
    expect(
      HomeWorkspaceRoute.myExpertsMemberKey(
        '/home-v2?global=expertHub&member=local/x',
      ),
      isNull,
    );
  });
}
