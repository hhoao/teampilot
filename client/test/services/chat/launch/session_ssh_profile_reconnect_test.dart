import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/launch/connect/chat_session_shell_factory.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';
import 'package:teampilot/cubits/chat_state.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/chat/session/session_open_request.dart';
import 'package:teampilot/services/chat/launch/session_launch_service.dart';
import 'package:teampilot/services/chat/session/session_data_store.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/chat/launch/connect/session_ssh_profile_reconnect.dart';
import 'package:teampilot/services/chat/launch/connect/ssh_reconnect_seats.dart';
import 'package:teampilot/services/chat/launch/connect/session_connect_job.dart';
import 'package:teampilot/services/chat/launch/launch_factory.dart';
import 'package:teampilot/services/chat/launch/session/session_launch_coordinator.dart';
import 'package:teampilot/services/chat/launch/session/session_launch_workspace_index.dart';
import 'package:teampilot/services/chat/session/session_lifecycle_service.dart';

import 'package:teampilot/services/terminal/terminal_session.dart';

import '../../../support/fake_terminal_session.dart';
import '../../../support/in_memory_filesystem.dart';

void main() {
  test('personal SSH reconnect delegates one existing-tab intent', () async {
    const profileId = 'profile-1';
    final workspace = Workspace(
      workspaceId: 'workspace-1',
      folders: const [WorkspaceFolder(path: '/work')],
      createdAt: 1,
    );
    final session = AppSession(
      sessionId: 'session-1',
      workspaceId: workspace.workspaceId,
      folders: workspace.folders,
      createdAt: 1,
    );
    final shell = FakeTerminalSession(fs: InMemoryFilesystem());
    shell.connect(workingDirectory: '/work');
    addTearDown(shell.dispose);
    final host = _ReconnectHost(
      lifecycle: _SshProfileLifecycle(
        RuntimeTarget.ssh(profileId, label: 'SSH'),
      ),
    );
    final coordinator = _RecordingReconnectCoordinator();
    final reconnect = SessionSshProfileReconnect(
      host: host,
      coordinator: coordinator,
      launchContextFor: (value) => WorkspaceLaunchContext(
        session: value,
        workspace: workspace,
        usesPosixPaths: true,
      ),
      workspaceIndex: () => SessionLaunchWorkspaceIndex(
        workspaces: [workspace],
        sessions: [session],
        usesPosixPaths: true,
      ),
      seats: _FakeReconnectSeats(
        openSessions: [
          SshReconnectOpenSession(
            sessionId: session.sessionId,
            session: session,
          ),
        ],
        resumeShells: {session.sessionId: shell},
      ),
    );

    await reconnect.reconnect(profileId);

    expect(coordinator.calls, hasLength(1));
    expect(coordinator.calls.single.sessionId, session.sessionId);
    expect(coordinator.calls.single.requests, hasLength(1));
    expect(coordinator.calls.single.requests.single.session, same(session));
    expect(coordinator.calls.single.requests.single.workspace, same(workspace));
    expect(
      coordinator.calls.single.requests.single.shellAcquisition,
      SessionShellAcquisition.personalResumeSession,
    );
    expect(shell.isRunning, isFalse);
  });

  test(
    'service reuses the displayed personal resume shell for reconnect jobs',
    () {
      final workspace = Workspace(
        workspaceId: 'workspace-1',
        folders: const [WorkspaceFolder(path: '/work')],
        createdAt: 1,
      );
      final session = AppSession(
        sessionId: 'session-1',
        workspaceId: workspace.workspaceId,
        folders: workspace.folders,
        createdAt: 1,
      );
      final tab = ChatTab(
        info: const ChatTabInfo(
          id: 'session-1',
          title: 'Session',
          subtitle: '',
        ),
        cliTeamName: '',
      )..persistedSession = session;
      final shell = FakeTerminalSession(fs: InMemoryFilesystem());
      tab.resumeSession = shell;
      addTearDown(shell.dispose);
      final host = _ReconnectHost(
        lifecycle: _SshProfileLifecycle(
          RuntimeTarget.ssh('profile-1', label: 'SSH'),
        ),
      );
      host.tabStore.registerSession(tab);
      final service = buildSessionLaunchService(
        host: host,
        storage: fakeHomeStorage(),
      );
      final job = SessionConnectJob(
        session: session,
        request: SessionOpenRequest(
          session: session,
          shellAcquisition: SessionShellAcquisition.personalResumeSession,
        ),
        generation: 1,
        workspace: workspace,
        reason: LaunchReason.sshReconnect,
      );

      final selected = service.shellForLaunch(job, session, (
        team: null,
        member: const TeamMemberConfig(id: 'session-1', name: 'Personal'),
        cli: CliTool.claude,
      ));

      expect(selected, same(shell));
      expect(tab.memberShells, isEmpty);
    },
  );

  test(
    'service falls back to the displayed personal member shell for reconnect jobs',
    () {
      final workspace = Workspace(
        workspaceId: 'workspace-1',
        folders: const [WorkspaceFolder(path: '/work')],
        createdAt: 1,
      );
      final session = AppSession(
        sessionId: 'session-1',
        workspaceId: workspace.workspaceId,
        folders: workspace.folders,
        createdAt: 1,
      );
      final tab = ChatTab(
        info: const ChatTabInfo(
          id: 'session-1',
          title: 'Session',
          subtitle: '',
        ),
        cliTeamName: '',
      )..persistedSession = session;
      final shell = FakeTerminalSession(fs: InMemoryFilesystem());
      tab.memberShells[session.sessionId] = shell;
      addTearDown(shell.dispose);
      final host = _ReconnectHost(
        lifecycle: _SshProfileLifecycle(
          RuntimeTarget.ssh('profile-1', label: 'SSH'),
        ),
      );
      host.tabStore.registerSession(tab);
      final service = buildSessionLaunchService(
        host: host,
        storage: fakeHomeStorage(),
      );
      final job = SessionConnectJob(
        session: session,
        request: SessionOpenRequest(
          session: session,
          shellAcquisition: SessionShellAcquisition.personalResumeSession,
        ),
        generation: 1,
        workspace: workspace,
        reason: LaunchReason.sshReconnect,
      );

      final selected = service.shellForLaunch(job, session, (
        team: null,
        member: const TeamMemberConfig(id: 'session-1', name: 'Personal'),
        cli: CliTool.claude,
      ));

      expect(selected, same(shell));
      expect(tab.resumeSession, isNull);
    },
  );

  test('team SSH reconnect delegates all affected roster members', () async {
    const profileId = 'profile-1';
    const members = [
      TeamMemberConfig(id: 'lead', name: 'Lead'),
      TeamMemberConfig(id: 'builder', name: 'Builder'),
    ];
    const team = TeamProfile(id: 'team-1', name: 'Team', members: members);
    final workspace = Workspace(
      workspaceId: 'workspace-1',
      folders: const [WorkspaceFolder(path: '/work')],
      createdAt: 1,
    );
    final session = AppSession(
      sessionId: 'session-1',
      workspaceId: workspace.workspaceId,
      folders: workspace.folders,
      sessionTeam: team.id,
      members: const [
        SessionMemberBinding(rosterMemberId: 'lead', taskId: 'task-lead'),
        SessionMemberBinding(rosterMemberId: 'builder', taskId: 'task-builder'),
      ],
      createdAt: 1,
    );
    final memberShells = <String, TerminalSession>{};
    for (final member in members) {
      final shell = FakeTerminalSession(fs: InMemoryFilesystem());
      shell.connect(workingDirectory: '/work');
      memberShells[member.id] = shell;
      addTearDown(shell.dispose);
    }
    final host = _ReconnectHost(
      lifecycle: _SshProfileLifecycle(
        RuntimeTarget.ssh(profileId, label: 'SSH'),
      ),
      team: team,
    );
    final coordinator = _RecordingReconnectCoordinator();
    final reconnect = SessionSshProfileReconnect(
      host: host,
      coordinator: coordinator,
      launchContextFor: (value) => WorkspaceLaunchContext(
        session: value,
        workspace: workspace,
        usesPosixPaths: true,
      ),
      workspaceIndex: () => SessionLaunchWorkspaceIndex(
        workspaces: [workspace],
        sessions: [session],
        usesPosixPaths: true,
      ),
      seats: _FakeReconnectSeats(
        openSessions: [
          SshReconnectOpenSession(
            sessionId: session.sessionId,
            session: session,
          ),
        ],
        memberShells: {session.sessionId: memberShells},
      ),
    );

    await reconnect.reconnect(profileId);

    expect(coordinator.calls, hasLength(1));
    expect(
      coordinator.calls.single.requests.map((request) => request.member?.id),
      orderedEquals(['lead', 'builder']),
    );
    expect(
      coordinator.calls.single.requests.every(
        (request) => request.team == team,
      ),
      isTrue,
    );
  });

  test('legacy team SSH reconnect expands an empty session roster', () async {
    const profileId = 'profile-1';
    const team = TeamProfile(
      id: 'team-legacy',
      name: 'Legacy',
      members: [
        TeamMemberConfig(id: 'team-lead', name: 'Lead'),
        TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 2),
      ],
    );
    final workspace = Workspace(
      workspaceId: 'workspace-1',
      folders: const [WorkspaceFolder(path: '/work')],
      createdAt: 1,
    );
    final session = AppSession(
      sessionId: 'session-legacy',
      workspaceId: workspace.workspaceId,
      folders: workspace.folders,
      sessionTeam: team.id,
      // Legacy records may have no session bindings at all.
      members: const [],
      createdAt: 1,
    );
    final memberShells = <String, TerminalSession>{};
    for (final id in ['team-lead', 'builder-0', 'builder-1']) {
      final shell = FakeTerminalSession(fs: InMemoryFilesystem());
      shell.connect(workingDirectory: '/work');
      memberShells[id] = shell;
      addTearDown(shell.dispose);
    }
    final host = _ReconnectHost(
      lifecycle: _SshProfileLifecycle(
        RuntimeTarget.ssh(profileId, label: 'SSH'),
      ),
      team: team,
    );
    final coordinator = _RecordingReconnectCoordinator();
    final reconnect = SessionSshProfileReconnect(
      host: host,
      coordinator: coordinator,
      launchContextFor: (value) => WorkspaceLaunchContext(
        session: value,
        workspace: workspace,
        usesPosixPaths: true,
      ),
      workspaceIndex: () => SessionLaunchWorkspaceIndex(
        workspaces: [workspace],
        sessions: [session],
        usesPosixPaths: true,
      ),
      seats: _FakeReconnectSeats(
        openSessions: [
          SshReconnectOpenSession(
            sessionId: session.sessionId,
            session: session,
          ),
        ],
        memberShells: {session.sessionId: memberShells},
      ),
    );

    await reconnect.reconnect(profileId);

    expect(coordinator.calls, hasLength(1));
    expect(
      coordinator.calls.single.requests.map((request) => request.member?.id),
      orderedEquals(['team-lead', 'builder-0', 'builder-1']),
    );
  });

  test('SSH reconnect waits for and propagates coordinator failure', () async {
    const profileId = 'profile-1';
    final workspace = Workspace(
      workspaceId: 'workspace-1',
      folders: const [WorkspaceFolder(path: '/work')],
      createdAt: 1,
    );
    final session = AppSession(
      sessionId: 'session-1',
      workspaceId: workspace.workspaceId,
      folders: workspace.folders,
      createdAt: 1,
    );
    final shell = FakeTerminalSession(fs: InMemoryFilesystem());
    shell.connect(workingDirectory: '/work');
    addTearDown(shell.dispose);

    final host = _ReconnectHost(
      lifecycle: _SshProfileLifecycle(
        RuntimeTarget.ssh(profileId, label: 'SSH'),
      ),
    );
    final coordinator = _RecordingReconnectCoordinator(
      entered: Completer<void>(),
      release: Completer<void>(),
      error: StateError('connect failed'),
    );
    final reconnect = SessionSshProfileReconnect(
      host: host,
      coordinator: coordinator,
      launchContextFor: (value) => WorkspaceLaunchContext(
        session: value,
        workspace: workspace,
        usesPosixPaths: true,
      ),
      workspaceIndex: () => SessionLaunchWorkspaceIndex(
        workspaces: [workspace],
        sessions: [session],
        usesPosixPaths: true,
      ),
      seats: _FakeReconnectSeats(
        openSessions: [
          SshReconnectOpenSession(
            sessionId: session.sessionId,
            session: session,
          ),
        ],
        resumeShells: {session.sessionId: shell},
      ),
    );

    final operation = reconnect.reconnect(profileId);
    var completed = false;
    final observed = operation.then<void>(
      (_) => completed = true,
      onError: (_) => completed = true,
    );
    await coordinator.entered!.future;
    await pumpEventQueue();
    expect(completed, isFalse);

    coordinator.release!.complete();
    await expectLater(operation, throwsA(isA<StateError>()));
    await observed;
  });
}

class _FakeReconnectSeats implements SshReconnectSeatPort {
  _FakeReconnectSeats({
    required this.openSessions,
    Map<String, TerminalSession>? resumeShells,
    Map<String, Map<String, TerminalSession>>? memberShells,
  }) : _resumeShells = resumeShells ?? const {},
       _memberShells = memberShells ?? const {};

  @override
  final Iterable<SshReconnectOpenSession> openSessions;
  final Map<String, TerminalSession> _resumeShells;
  final Map<String, Map<String, TerminalSession>> _memberShells;

  @override
  TerminalSession? memberShell(String sessionId, String memberId) =>
      _memberShells[sessionId]?[memberId];

  @override
  TerminalSession? personalResumeShell(String sessionId, AppSession session) {
    final resume = _resumeShells[sessionId];
    if (resume != null && !resume.isDisposed) return resume;
    final byId = _memberShells[sessionId]?[session.sessionId];
    if (byId != null && !byId.isDisposed) return byId;
    return null;
  }

  @override
  Future<void> closeMemberRemotePlane(String sessionId, String memberId) async {}
}

class _RecordingReconnectCoordinator implements SessionReconnectIntentPort {
  _RecordingReconnectCoordinator({this.entered, this.release, this.error});

  final calls = <({String sessionId, List<SessionOpenRequest> requests})>[];
  final Completer<void>? entered;
  final Completer<void>? release;
  final Object? error;

  @override
  Future<void> reconnectTab(
    String sessionId,
    Iterable<SessionOpenRequest> requests,
  ) async {
    calls.add((sessionId: sessionId, requests: requests.toList()));
    entered?.complete();
    if (release != null) await release!.future;
    if (error != null) throw error!;
  }
}

class _ReconnectHost implements SessionLaunchHost {
  _ReconnectHost({required this.lifecycle, this.team})
    : tabStore = ChatTabStore(storage: fakeHomeStorage()),
      dataStore = SessionDataStore(storage: fakeHomeStorage());

  @override
  final SessionLifecycleService lifecycle;
  final TeamProfile? team;

  @override
  final ChatTabStore tabStore;

  @override
  final SessionDataStore dataStore;

  @override
  final ChatSessionShellFactory shellFactory = ChatSessionShellFactory(
    executableResolver: () => 'true',
  );

  @override
  bool get isClosed => false;

  @override
  Future<TeamProfile?> teamProfileById(String teamId) async => team;

  @override
  PostFrameScheduler get postFrameScheduler =>
      (callback) => callback();

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
