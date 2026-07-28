import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/session_connect_request.dart';
import 'package:teampilot/cubits/chat/session_launch_retry.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';

AppSession _simpleSession() => AppSession(
  sessionId: 's1',
  workspaceId: 'w1',
  folders: const [WorkspaceFolder(path: '/w')],
  cli: CliTool.claude,
  provider: 'anthropic',
  model: 'claude-sonnet',
  effort: 'high',
  createdAt: 1,
  updatedAt: 1,
);

AppSession _teamSession() => AppSession(
  sessionId: 's2',
  workspaceId: 'w1',
  folders: const [WorkspaceFolder(path: '/w')],
  sessionTeam: 'team-1',
  createdAt: 1,
  updatedAt: 1,
);

TeamProfile _team() => const TeamProfile(
  id: 'team-1',
  name: 'Team',
  members: [
    TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
    TeamMemberConfig(id: 'developer', name: 'Developer'),
  ],
);

TeamProfile _teamWithoutLead() => const TeamProfile(
  id: 'team-1',
  name: 'Team',
  members: [
    TeamMemberConfig(id: 'developer', name: 'Developer'),
    TeamMemberConfig(id: 'reviewer', name: 'Reviewer'),
  ],
);

void main() {
  test('simple session has no team/member and preserves workbench', () {
    final req = buildRetryExistingSessionConnect(
      session: _simpleSession(),
      selectedMemberId: 's1',
    );
    expect(req, isA<ExistingSessionConnect>());
    final existing = req!;
    expect(existing.preserveWorkbenchView, isTrue);
    expect(existing.team, isNull);
    expect(existing.member, isNull);
  });

  test('team uses selected member when present', () {
    final req = buildRetryExistingSessionConnect(
      session: _teamSession(),
      selectedMemberId: 'developer',
      team: _team(),
    )!;
    expect(req.member?.id, 'developer');
    expect(req.preserveWorkbenchView, isTrue);
  });

  test('team falls back to lead when selection missing', () {
    final req = buildRetryExistingSessionConnect(
      session: _teamSession(),
      selectedMemberId: '',
      team: _team(),
    )!;
    expect(req.member?.id, 'team-lead');
  });

  test('team without lead falls back to first member when selection empty', () {
    final req = buildRetryExistingSessionConnect(
      session: _teamSession(),
      selectedMemberId: '',
      team: _teamWithoutLead(),
    )!;
    expect(req.member?.id, 'developer');
  });

  test('toggle path can force preserveWorkbenchView false', () {
    final req = buildRetryExistingSessionConnect(
      session: _simpleSession(),
      selectedMemberId: 's1',
      preserveWorkbenchView: false,
    )!;
    expect(req.preserveWorkbenchView, isFalse);
  });

  test('team session returns null without a team profile', () {
    final req = buildRetryExistingSessionConnect(
      session: _teamSession(),
      selectedMemberId: 'developer',
    );
    expect(req, isNull);
  });
}
