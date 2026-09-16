import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_state.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat/session_launch_host.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/launch/connect_shell_result.dart';
import 'package:teampilot/services/launch/session_member_connect_scheduler.dart';
import 'package:teampilot/services/launch/session_shell_connector.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('schedule passes workspace from lookup into shell connect', () async {
    const workspaceId = 'ws-1';
    final workspace = Workspace(
      workspaceId: workspaceId,
      createdAt: 1,
      folders: const [
        WorkspaceFolder(path: '/local', targetId: WorkspaceFolder.localTargetId),
        WorkspaceFolder(path: '/home', targetId: 'ssh:home'),
      ],
    );
    final session = AppSession(
      sessionId: 'sess-1',
      workspaceId: workspaceId,
      createdAt: 1,
    );
    final tab = ChatTab(
      info: ChatTabInfo(id: 'sess-1', title: 'Team', subtitle: ''),
      cliTeamName: 'team-1',
      workspaceId: workspaceId,
    )..persistedSession = session;
    final team = TeamProfile(
      id: 'team-1',
      name: 'Team',
      cli: CliTool.claude,
      members: const [TeamMemberConfig(id: 'm1', name: 'Member')],
    );
    final member = team.members.single;
    final shell = TerminalSession(executable: 'true', fs: InMemoryFilesystem());
    final tabStore = ChatTabStore(storage: fakeHomeStorage())
      ..setActiveWorkspaceId(workspaceId)
      ..registerSession(tab);

    final host = _ImmediateFrameHost(tabStore);
    final connector = _RecordingConnector(host, _FakeDelegate());
    final scheduler = SessionMemberConnectScheduler(
      host: host,
      shellConnector: connector,
      shellForLaunch: ({
        required tab,
        required shellKey,
        required cli,
        required session,
        rosterMemberId,
      }) =>
          shell,
      sessionForMemberConnect: (_, __) => session,
      tabStore: tabStore,
      workspaceById: (id) => id == workspaceId ? workspace : null,
    );

    scheduler.schedule(team, member, tab, selectMember: false);

    expect(connector.lastWorkspace, same(workspace));
    expect(connector.lastSession?.sessionId, 'sess-1');
  });
}

class _RecordingConnector extends SessionShellConnector {
  _RecordingConnector(super.host, super.delegate)
    : super(isLocalNative: () => true);

  Workspace? lastWorkspace;
  AppSession? lastSession;

  @override
  Future<ConnectShellResult> connect({
    required ChatTab tab,
    required AppSession session,
    required TerminalSession shell,
    SessionRepository? repo,
    required bool launched,
    TeamProfile? team,
    TeamMemberConfig? member,
    Workspace? workspace,
  }) async {
    lastWorkspace = workspace;
    lastSession = session;
    return ConnectShellResult.attached;
  }
}

class _ImmediateFrameHost implements SessionLaunchHost {
  _ImmediateFrameHost(this.tabStore)
    : lifecycle = SessionLifecycleService(
        storage: fakeHomeStorage(),
        loadPresets: () => const [],
      ),
      state = ChatState();

  @override
  final ChatTabStore tabStore;

  @override
  final SessionLifecycleService lifecycle;

  @override
  ChatState state;

  @override
  PostFrameScheduler get postFrameScheduler => (cb) => cb();

  @override
  bool get hasConnectingSession => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeDelegate implements SessionShellConnectorDelegate {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
