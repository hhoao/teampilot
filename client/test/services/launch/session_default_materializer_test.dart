import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_state.dart';
import 'package:teampilot/cubits/chat/model/session_open_status.dart';
import 'package:teampilot/cubits/chat/session_data_store.dart';
import 'package:teampilot/cubits/chat/session_launch_host.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_continue_overrides.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/launch/session_default_materializer.dart';
import 'package:teampilot/services/launch/session_launch_workspace_index.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';

void main() {
  group('SessionDefaultMaterializer', () {
    test('personal session patches the snapshot without a full reload', () async {
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: const [WorkspaceFolder(path: '/proj')],
        createdAt: 1,
        updatedAt: 1,
      );
      final host = _MaterializeHost(ChatState(workspaces: [workspace]));
      final openedSessions = <String>[];
      final materializer = SessionDefaultMaterializer(
        host: host,
        openSession: (request) async {
          openedSessions.add(request.session.sessionId);
          return SessionOpenStatus.opened;
        },
        workspaceIndex: () => SessionLaunchWorkspaceIndex(
          workspaces: host.state.workspaces,
          sessions: host.state.sessions,
        ),
        isTabsEmpty: () => true,
        activeBucketKey: () => 'ws-1',
      );
      final repo = _MaterializeRepo();
      final newSession = AppSession(
        sessionId: 'sess-new',
        workspaceId: 'ws-1',
        createdAt: 2,
        updatedAt: 2,
      );
      repo.created = (
        session: newSession,
        workspace: workspace.copyWith(sessionIds: const ['sess-new']),
      );

      await materializer.materializePersonalSession(
        workspace,
        repo,
        connectImmediately: false,
      );

      expect(repo.createCalls, 1);
      expect(host.loadWorkspaceDataCalls, 0,
          reason: 'materializer must not rescan after create');
      expect(openedSessions, ['sess-new']);
      expect(host.emitted, isNotEmpty);
      final last = host.emitted.last;
      expect(
        last.sessions.map((s) => s.sessionId),
        contains('sess-new'),
      );
      expect(
        last.workspaces.single.sessionIds,
        contains('sess-new'),
      );
    });

    test('team session patches the snapshot without a full reload', () async {
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: const [WorkspaceFolder(path: '/proj')],
        createdAt: 1,
        updatedAt: 1,
      );
      final team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        members: const [
          TeamMemberConfig(id: 'lead', name: 'Lead'),
          TeamMemberConfig(id: 'builder', name: 'Builder'),
        ],
        cli: CliTool.claude,
      );
      final host = _MaterializeHost(ChatState(workspaces: [workspace]));
      final openedSessions = <String>[];
      final materializer = SessionDefaultMaterializer(
        host: host,
        openSession: (request) async {
          openedSessions.add(request.session.sessionId);
          return SessionOpenStatus.opened;
        },
        workspaceIndex: () => SessionLaunchWorkspaceIndex(
          workspaces: host.state.workspaces,
          sessions: host.state.sessions,
        ),
        isTabsEmpty: () => true,
        activeBucketKey: () => 'ws-1',
      );
      final repo = _MaterializeRepo();
      final newSession = AppSession(
        sessionId: 'sess-team',
        workspaceId: 'ws-1',
        sessionTeam: 'team-1',
        createdAt: 2,
        updatedAt: 2,
      );
      repo.created = (
        session: newSession,
        workspace: workspace.copyWith(sessionIds: const ['sess-team']),
      );

      await materializer.materializeTeamSession(
        team,
        repo,
        connectImmediately: false,
        memberForInitialShell: team.members.first,
        workspaceCwd: '/proj',
      );

      expect(repo.createCalls, 1);
      expect(repo.lastSessionTeam, 'team-1');
      expect(host.loadWorkspaceDataCalls, 0,
          reason: 'materializer must not rescan after create');
      expect(openedSessions, ['sess-team']);
      expect(host.emitted, isNotEmpty);
      final last = host.emitted.last;
      expect(
        last.sessions.map((s) => s.sessionId),
        contains('sess-team'),
      );
      expect(
        last.workspaces.single.sessionIds,
        contains('sess-team'),
      );
    });
  });
}

class _MaterializeHost implements SessionLaunchHost {
  _MaterializeHost(this.state)
    : lifecycle = SessionLifecycleService(loadPresets: () => const []);

  @override
  ChatState state;

  @override
  final SessionLifecycleService lifecycle;

  @override
  bool get isClosed => false;

  @override
  SessionDataStore get dataStore => _dataStore;
  final SessionDataStore _dataStore = SessionDataStore();

  final emitted = <ChatDataSnapshot>[];
  int loadWorkspaceDataCalls = 0;

  @override
  ChatDataSnapshot stateSnapshot() => ChatDataSnapshot(
        workspaces: state.workspaces,
        sessions: state.sessions,
        visibleWorkspaces: state.visibleWorkspaces,
        visibleSessions: state.visibleSessions,
      );

  @override
  void emitSnapshot(ChatDataSnapshot snapshot) {
    emitted.add(snapshot);
    state = state.copyWith(
      workspaces: snapshot.workspaces,
      sessions: snapshot.sessions,
      visibleWorkspaces: snapshot.visibleWorkspaces,
      visibleSessions: snapshot.visibleSessions,
    );
  }

  @override
  void appendSessionSnapshot(AppSession session) {
    emitSnapshot(_dataStore.appendSession(stateSnapshot(), session));
  }

  @override
  Future<void> loadWorkspaceData(SessionRepository repo) async {
    loadWorkspaceDataCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) return null;
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

class _MaterializeRepo extends Fake implements SessionRepository {
  ({AppSession session, Workspace workspace})? created;
  int createCalls = 0;
  String? lastSessionTeam;

  @override
  Future<({AppSession session, Workspace workspace})> createSession(
    String workspaceId, {
    String sessionTeam = '',
    SessionPurpose purpose = SessionPurpose.normal,
    String workflowId = '',
    List<TeamMemberConfig> rosterMembers = const [],
    Map<String, CliTool> memberClis = const {},
    CliTool? cli,
    String? provider,
    String? model,
    String? effort,
    String? presetId,
    String? workingDirectory,
    String? fixedSessionId,
    String? expertKey,
    SessionContinueOverrides? continueOverrides,
    List<SessionMemberBinding>? members,
    Map<String, String>? memberTargets,
    Workspace? knownWorkspace,
  }) async {
    createCalls++;
    lastSessionTeam = sessionTeam;
    return created!;
  }
}
