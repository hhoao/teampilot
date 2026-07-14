import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/landing_launch_context.dart';
import 'package:teampilot/utils/workspace_active_context.dart';

void main() {
  test('idle hides team chrome', () {
    expect(WorkspaceActiveContext.idle.isPersonal, isTrue);
    expect(WorkspaceActiveContext.idle.team, isNull);
    expect(WorkspaceActiveContext.idle.activeSessionId, isNull);
  });

  test('landing context is personal for simple mode', () {
    const landing = LandingLaunchContext(isPersonal: true);
    expect(landing.isPersonal, isTrue);
    expect(landing.teamId, isNull);
  });

  test('landing context resolves team id', () {
    const landing = LandingLaunchContext(
      isPersonal: false,
      teamId: 'team-alpha',
    );
    expect(landing.isPersonal, isFalse);
    expect(landing.teamId, 'team-alpha');
  });
}
