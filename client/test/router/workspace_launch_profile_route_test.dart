import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_route.dart';

void main() {
  test('profile query decodes manage deep link identity', () {
    expect(
      HomeWorkspaceRoute.profile(
        '/home-v2/workspace/ws-1?view=manage&section=members&profile=team-1',
      ),
      'team-1',
    );
    expect(HomeWorkspaceRoute.profile('/home-v2/workspace/ws-1'), isNull);
  });
}
