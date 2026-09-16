import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat/session_launch_host.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/launch/connect_shell_result.dart';
import 'package:teampilot/services/launch/session_launch_workspace_index.dart';
import 'package:teampilot/services/launch/session_shell_connector.dart';
import 'package:teampilot/services/launch/session_ssh_profile_reconnect.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../../support/fake_terminal_session.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  group('throwIfReconnectConnectFailed', () {
    test('failed connect result is a reconnect error', () {
      expect(
        () => throwIfReconnectConnectFailed(ConnectShellResult.failed),
        throwsA(isA<StateError>()),
      );
    });

    test('attached connect result is success', () {
      throwIfReconnectConnectFailed(ConnectShellResult.attached);
    });
  });

  group('reconnect personal tab', () {
    test('failed personal reconnect fails the session-plane callback', () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      const profileId = 'profile-1';
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: const [WorkspaceFolder(path: '/work')],
        createdAt: 1,
      );
      final session = AppSession(
        sessionId: 'sess-1',
        workspaceId: workspace.workspaceId,
        folders: const [WorkspaceFolder(path: '/work')],
        createdAt: 1,
      );
      final tab = ChatTab(
        info: const ChatTabInfo(id: 'sess-1', title: 'S', subtitle: ''),
        cliTeamName: '',
      )..persistedSession = session;
      final shell = FakeTerminalSession(fs: InMemoryFilesystem());
      tab.resumeSession = shell;
      addTearDown(shell.dispose);

      final host = _ReconnectHost(
        lifecycle: _SshProfileLifecycle(
          RuntimeTarget.ssh(profileId, label: 'ssh'),
        ),
      );
      final reconnect = SessionSshProfileReconnect(
        host: host,
        shellConnector: _FailingShellConnector(host),
        launchContextFor: (s) => WorkspaceLaunchContext(
          session: s,
          workspace: workspace,
          usesPosixPaths: true,
        ),
        scheduleMemberConnect: (_, _, _, {bool selectMember = false}) {},
        workspaceIndex: () => SessionLaunchWorkspaceIndex(
          workspaces: [workspace],
          sessions: [session],
          usesPosixPaths: true,
        ),
        openTabs: () => [tab],
      );

      await expectLater(
        reconnect.reconnect(profileId),
        throwsA(isA<StateError>()),
      );
      expect(host.failedSessionIds, ['sess-1']);
      expect(tab.membersPendingConnect, isEmpty);
    });
  });
}

class _ReconnectHost implements SessionLaunchHost {
  _ReconnectHost({required this.lifecycle});

  @override
  final SessionLifecycleService lifecycle;

  final failedSessionIds = <String>[];

  @override
  bool get isClosed => false;

  @override
  void failSessionConnect(
    String sessionId,
    String rawMessage, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    failedSessionIds.add(sessionId);
  }

  @override
  void beginSessionConnect(String sessionId) {}

  @override
  void updateTabRunning(String tabId) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _SshProfileLifecycle extends SessionLifecycleService {
  _SshProfileLifecycle(this.target) : super(storage: fakeHomeStorage());

  final RuntimeTarget target;

  @override
  RuntimeTarget launchWorkTarget(
    WorkspaceLaunchContext ctx, {
    String? memberId,
  }) => target;
}

class _UnusedDelegate implements SessionShellConnectorDelegate {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FailingShellConnector extends SessionShellConnector {
  _FailingShellConnector(SessionLaunchHost host)
    : super(host, _UnusedDelegate(), isLocalNative: () => true);

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
  }) async => ConnectShellResult.failed;
}
