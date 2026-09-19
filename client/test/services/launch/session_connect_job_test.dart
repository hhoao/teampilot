import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/model/chat_tab.dart';
import 'package:teampilot/services/chat/model/chat_tab_info.dart';
import 'package:teampilot/services/chat/model/session_open_request.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/chat/launch/connect/session_connect_job.dart';

void main() {
  final workspace = Workspace(
    workspaceId: 'workspace-1',
    folders: const [WorkspaceFolder(path: '/workspace')],
    createdAt: 1,
  );
  const team = TeamProfile(
    id: 'team-1',
    name: 'Team',
    members: [TeamMemberConfig(id: 'member-1', name: 'Member')],
  );
  const member = TeamMemberConfig(id: 'member-1', name: 'Member');
  final session = AppSession(
    sessionId: 'session-1',
    workspaceId: workspace.workspaceId,
    folders: workspace.folders,
    sessionTeam: team.id,
    createdAt: 1,
  );
  final tab = ChatTab(
    info: const ChatTabInfo(id: 'session-1', title: 'Session', subtitle: ''),
    cliTeamName: team.id,
  );
  final request = SessionOpenRequest(
    session: session,
    workspace: workspace,
    team: team,
    member: member,
  );

  SessionConnectJob personalJob() => SessionConnectJob(
    tab: tab,
    session: AppSession(
      sessionId: 'personal-session',
      workspaceId: workspace.workspaceId,
      folders: workspace.folders,
      createdAt: 1,
    ),
    request: SessionOpenRequest(session: session),
    generation: 1,
    workspace: workspace,
    reason: LaunchReason.create,
  );

  test('job identity uses session and selected member', () {
    final job = SessionConnectJob(
      tab: tab,
      session: session,
      request: request,
      generation: 3,
      workspace: workspace,
      team: team,
      member: member,
      reason: LaunchReason.openExisting,
    );

    expect(job.sessionId, session.sessionId);
    expect(job.memberId, member.id);
    expect(job.generation, 3);
    expect(job.reason, LaunchReason.openExisting);
  });

  test('personal job uses session id as member identity', () {
    final job = personalJob();
    expect(job.memberId, job.session.sessionId);
  });
}
