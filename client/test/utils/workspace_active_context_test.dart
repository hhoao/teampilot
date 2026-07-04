import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/landing_launch_context.dart';
import 'package:teampilot/utils/workspace_active_context.dart';

void main() {
  test('idle hides team chrome', () {
    expect(WorkspaceActiveContext.idle.isPersonal, isTrue);
    expect(WorkspaceActiveContext.idle.team, isNull);
    expect(WorkspaceActiveContext.idle.activeSessionId, isNull);
  });

  test('landing profile id resolves personal default', () {
    const landing = LandingLaunchContext(isPersonal: true);
    expect(landing.profileId, isNotEmpty);
  });

  test('landing profile id resolves team id', () {
    const landing = LandingLaunchContext(
      isPersonal: false,
      teamId: 'team-alpha',
    );
    expect(landing.profileId, 'team-alpha');
  });
}
