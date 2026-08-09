import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/chat/model/session_connect_request.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/cli/claude/capabilities/config_profile.dart';
import 'package:teampilot/services/expert_hub/expert_member_materializer.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';
import 'package:teampilot/utils/team/team_member_naming.dart';

import '../support/fake_terminal_session.dart';
import '../support/fixed_resume_lifecycle_service.dart';
import '../support/post_frame_test_harness.dart';
import '../support/test_runtime_context.dart';

String _testExecutable() => 'flashskyai';

Future<void> _deleteTempDirBestEffort(Directory dir) =>
    deleteTempDirBestEffort(dir);

Future<void> _tearDownChatCubitWithSessionPersist(
  ChatCubit cubit,
  PostFrameTestHarness postFrame,
) => tearDownChatCubitWithSessionPersist(cubit, postFrame);

void main() {
  setUp(() {
    setUpTestAppStorage();
  });

  tearDown(() {
    tearDownTestAppStorage();
  });

  test('opening a team session tab starts team-lead member shell', () async {
    final team = await ExpertMemberMaterializer.attachMaterializedMembers(
      TeamProfile(
        id: LaunchProfileProvisioner.defaultNativeTeamId,
        name: 'Default Native Team',
        roster: TeamMemberNaming.defaultRoster(),
      ),
    );
    final postFrame = PostFrameTestHarness();
    final repo = SessionRepository(
      rootDir: (await Directory.systemTemp.createTemp('sidebar_sess_')).path,
    );
    final workspace = await repo.createWorkspace([
      WorkspaceFolder(path: '/work/current'),
    ]);
    final session = await repo.createSession(
      workspace.workspaceId,
      sessionTeam: team.id,
      rosterMembers: team.members,

      memberClis: {for (final m in team.members) m.id: CliTool.claude},
    );
    final chatCubit = ChatCubit(
      executableResolver: _testExecutable,
      automationRepository: testAutomationRepository(),
      sessionRepository: repo,
      terminalSessionFactory:
          ({required String executable, int scrollbackLines = 10000}) =>
              FakeTerminalSession(
                executable: executable,
                scrollbackLines: scrollbackLines,
              ),
      postFrameScheduler: postFrame.scheduler,
      lifecycleService: FixedResumeLifecycleService(resume: false),
    );
    addTearDown(chatCubit.close);
    await chatCubit.loadWorkspaceData(repo);

    await chatCubit.requestOpenSession(
      SessionOpenRequest(
        session: session,
        team: team,
        member: team.members.first,
        repo: repo,
      ),
    );
    await drainPendingAsyncWork();
    await postFrame.flush();

    expect(chatCubit.state.activeSessionId, session.sessionId);
    expect(chatCubit.state.selectedMemberId, 'team-lead');
    expect(chatCubit.isMemberRunning(sessionId: session.sessionId, memberId: 'team-lead'), isTrue);
  });

  test('chat cubit manages tabs and selection', () {
    final cubit = ChatCubit(
      executableResolver: _testExecutable,
      automationRepository: testAutomationRepository(),
    );
    expect(cubit.state.tabs, isEmpty);
    expect(cubit.state.selectedMemberId, isEmpty);

    final team = TeamProfile(
      id: 'test-team',
      name: 'Test',
      members: const [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        TeamMemberConfig(id: 'dev', name: 'developer'),
      ],
    );

    cubit.syncTeam(team);
    expect(cubit.state.selectedMemberId, 'team-lead');

    cubit.selectMember('dev');
    expect(cubit.state.selectedMemberId, 'dev');
  });

  test('chat cubit opens member shells inside one session tab', () async {
    final postFrame = PostFrameTestHarness();
    final cubit = ChatCubit(
      executableResolver: _testExecutable,
      automationRepository: testAutomationRepository(),
      terminalSessionFactory:
          ({required String executable, int scrollbackLines = 10000}) =>
              FakeTerminalSession(
                executable: executable,
                scrollbackLines: scrollbackLines,
              ),
      postFrameScheduler: postFrame.scheduler,
    );
    final team = TeamProfile(
      id: 'test-team',
      name: 'Test',
      members: const [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        TeamMemberConfig(id: 'dev', name: 'developer'),
      ],
    );

    await cubit.openMemberTab(team, team.members[0]);
    await cubit.openMemberTab(team, team.members[1]);
    await postFrame.flush();

    expect(cubit.state.tabs.length, 1);
    expect(cubit.state.tabs.single.id, 'local-test-team');
    expect(cubit.state.selectedMemberId, 'dev');
    expect(cubit.isMemberRunning(sessionId: cubit.state.activeSessionId!, memberId: 'team-lead'), isTrue);
    expect(cubit.isMemberRunning(sessionId: cubit.state.activeSessionId!, memberId: 'dev'), isTrue);
  });

  test(
    'chat cubit launches Claude members with team dir and settings file',
    () async {
      final tmp = await Directory.systemTemp.createTemp('chat_claude_cfg_');
      addTearDown(() => _deleteTempDirBestEffort(tmp));
      final sessions = <FakeTerminalSession>[];
      final postFrame = PostFrameTestHarness();
      final cubit = ChatCubit(
        executableResolver: () => 'claude',
        automationRepository: testAutomationRepository(),
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) {
              final session = FakeTerminalSession(executable: executable);
              sessions.add(session);
              return session;
            },
        postFrameScheduler: postFrame.scheduler,
        lifecycleService: SessionLifecycleService(
          storageRootsResolver: () async => testRuntimeContext(tmp.path),
        ),
      );
      const team = TeamProfile(
        id: 'test-team',
        name: 'Test',
        cli: CliTool.claude,
        members: [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead', model: 'opus'),
          TeamMemberConfig(id: 'dev', name: 'developer', model: 'sonnet'),
        ],
      );

      await cubit.openMemberTab(team, team.members[1]);
      await postFrame.flush();

      expect(sessions, hasLength(1));
      final claudeDir =
          sessions.single.lastExtraEnvironments.single?['CLAUDE_CONFIG_DIR'];
      expect(claudeDir, isNotNull);
      expect(claudeDir, contains(p.join('workspace', 'workspaces')));
      expect(claudeDir, endsWith(p.join('runtime', 'claude')));
      expect(
        sessions
            .single
            .lastExtraEnvironments
            .single?[ClaudeConfigProfileCapability.settingsFileEnvKey],
        p.join(claudeDir!, 'settings', 'dev.json'),
      );
    },
  );

  test(
    'chat cubit connectSession starts all members when auto-launch enabled',
    () async {
      final tmp = await Directory.systemTemp.createTemp('connect_all_');
      addTearDown(() => _deleteTempDirBestEffort(tmp));
      final repo = SessionRepository(rootDir: tmp.path);
      final postFrame = PostFrameTestHarness();
      final team = TeamProfile(
        id: 'test-team',
        name: 'Test',
        members: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'developer'),
        ],
      );
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/wd'),
      ]);
      await repo.createSession(
        workspace.workspaceId,
        sessionTeam: team.id,
        rosterMembers: team.members,

        memberClis: {for (final m in team.members) m.id: CliTool.claude},
      );
      final cubit = ChatCubit(
        executableResolver: _testExecutable,
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                FakeTerminalSession(
                  executable: executable,
                  scrollbackLines: scrollbackLines,
                ),
        postFrameScheduler: postFrame.scheduler,
        autoLaunchAllMembersOnConnect: () => true,
      );
      addTearDown(() => _tearDownChatCubitWithSessionPersist(cubit, postFrame));
      await cubit.loadWorkspaceData(repo);

      cubit.syncTeam(team);
      await cubit.connectWorkspaceSession(TeamSessionConnect(team), repo: repo);
      await drainPendingAsyncWork();
      await postFrame.flush();

      expect(cubit.state.tabs.length, 1);
      expect(cubit.isMemberRunning(sessionId: cubit.state.activeSessionId!, memberId: 'team-lead'), isTrue);
      expect(cubit.isMemberRunning(sessionId: cubit.state.activeSessionId!, memberId: 'dev'), isTrue);
      expect(cubit.state.selectedMemberId, 'team-lead');
    },
  );

  test(
    'chat cubit connectSession starts only selected member by default',
    () async {
      final tmp = await Directory.systemTemp.createTemp('connect_one_');
      addTearDown(() => _deleteTempDirBestEffort(tmp));
      final repo = SessionRepository(rootDir: tmp.path);
      final postFrame = PostFrameTestHarness();
      final team = TeamProfile(
        id: 'test-team',
        name: 'Test',
        members: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'developer'),
        ],
      );
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/wd'),
      ]);
      await repo.createSession(
        workspace.workspaceId,
        sessionTeam: team.id,
        rosterMembers: team.members,

        memberClis: {for (final m in team.members) m.id: CliTool.claude},
      );
      final cubit = ChatCubit(
        executableResolver: _testExecutable,
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                FakeTerminalSession(
                  executable: executable,
                  scrollbackLines: scrollbackLines,
                ),
        postFrameScheduler: postFrame.scheduler,
      );
      addTearDown(() => _tearDownChatCubitWithSessionPersist(cubit, postFrame));
      await cubit.loadWorkspaceData(repo);

      cubit.syncTeam(team);
      await cubit.connectWorkspaceSession(TeamSessionConnect(team), repo: repo);
      await drainPendingAsyncWork();
      await postFrame.flush();

      expect(cubit.state.tabs.length, 1);
      expect(cubit.isMemberRunning(sessionId: cubit.state.activeSessionId!, memberId: 'team-lead'), isTrue);
      expect(cubit.isMemberRunning(sessionId: cubit.state.activeSessionId!, memberId: 'dev'), isFalse);
      expect(cubit.state.selectedMemberId, 'team-lead');
    },
  );

  test(
    'chat cubit keeps persisted session tabs separate from member selection',
    () async {
      final postFrame = PostFrameTestHarness();
      final cubit = ChatCubit(
        executableResolver: _testExecutable,
        automationRepository: testAutomationRepository(),
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                FakeTerminalSession(
                  executable: executable,
                  scrollbackLines: scrollbackLines,
                ),
        postFrameScheduler: postFrame.scheduler,
      );
      final team = TeamProfile(
        id: 'test-team',
        name: 'Test',
        members: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'developer'),
        ],
      );
      final session = AppSession(
        sessionId: 'session-1',
        workspaceId: 'proj-test-2',
        folders: const [WorkspaceFolder(path: '/tmp')],
        display: 'Session One',
        sessionTeam: 'test-team',
        cliTeamName: 'test-team-1',
        members: [
          SessionMemberBinding(
            rosterMemberId: 'team-lead',
            taskId: 'task-lead',
          ),
          SessionMemberBinding(rosterMemberId: 'dev', taskId: 'task-dev'),
        ],
        createdAt: 1,
        updatedAt: 1,
      );

      await cubit.requestOpenSession(
        SessionOpenRequest(
          session: session,
          team: team,
          member: team.members.first,
        ),
      );
      await drainPendingAsyncWork();
      await cubit.openMemberTab(team, team.members[0]);
      await cubit.openMemberTab(team, team.members[1]);
      await drainPendingAsyncWork();
      await postFrame.flush();

      expect(cubit.state.tabs.length, 1);
      expect(cubit.state.tabs.single.id, 'session-1');
      expect(cubit.state.activeSessionId, 'session-1');
      expect(cubit.state.selectedMemberId, 'dev');
      expect(cubit.isMemberRunning(sessionId: cubit.state.activeSessionId!, memberId: 'team-lead'), isTrue);
      expect(cubit.isMemberRunning(sessionId: cubit.state.activeSessionId!, memberId: 'dev'), isTrue);
    },
  );

  test('openSessionTab first launch uses session-id not resume', () async {
    final tmp = await Directory.systemTemp.createTemp('open_sess_');
    addTearDown(() => _deleteTempDirBestEffort(tmp));
    final repo = SessionRepository(rootDir: tmp.path);
    final team = TeamProfile(
      id: 'tid',
      name: 'TName',
      members: const [TeamMemberConfig(id: 'lid', name: 'team-lead')],
    );
    final workspace = await repo.createWorkspace([
      WorkspaceFolder(path: '/wd'),
    ]);
    await repo.createSession(
      workspace.workspaceId,
      sessionTeam: team.id,
      rosterMembers: team.members,

      memberClis: {for (final m in team.members) m.id: CliTool.claude},
    );
    FakeTerminalSession? captured;
    final postFrame = PostFrameTestHarness();
    final cubit = ChatCubit(
      executableResolver: _testExecutable,
      automationRepository: testAutomationRepository(),
      terminalSessionFactory:
          ({required String executable, int scrollbackLines = 10000}) {
            captured = FakeTerminalSession(executable: executable);
            return captured!;
          },
      postFrameScheduler: postFrame.scheduler,
    );
    addTearDown(() => _tearDownChatCubitWithSessionPersist(cubit, postFrame));
    await cubit.loadWorkspaceData(repo);
    final rel = cubit.state.sessions.single;
    await cubit.requestOpenSession(
      SessionOpenRequest(
        session: rel,
        team: team,
        member: team.members.first,
        repo: repo,
      ),
    );
    await drainPendingAsyncWork();
    await postFrame.flush();
    await drainPendingAsyncWork();
    expect(captured, isNotNull);
    expect(captured!.lastResumeSessionIds.last, isNull);
    expect(captured!.lastFixedSessionIds.last, rel.members.single.taskId);
  });

  test('openSessionTab started session uses resume not session-id', () async {
    final tmp = await Directory.systemTemp.createTemp('open_sess_');
    addTearDown(() => _deleteTempDirBestEffort(tmp));
    final repo = SessionRepository(rootDir: tmp.path);
    final team = TeamProfile(
      id: 'tid',
      name: 'TName',
      members: const [TeamMemberConfig(id: 'lid', name: 'team-lead')],
    );
    final workspace = await repo.createWorkspace([
      WorkspaceFolder(path: '/wd'),
    ]);
    final session = await repo.createSession(
      workspace.workspaceId,
      sessionTeam: team.id,
      rosterMembers: team.members,

      memberClis: {for (final m in team.members) m.id: CliTool.claude},
    );
    await repo.markSessionLaunched(session.sessionId);

    FakeTerminalSession? captured;
    final postFrame = PostFrameTestHarness();
    final cubit = ChatCubit(
      executableResolver: _testExecutable,
      automationRepository: testAutomationRepository(),
      terminalSessionFactory:
          ({required String executable, int scrollbackLines = 10000}) {
            captured = FakeTerminalSession(executable: executable);
            return captured!;
          },
      postFrameScheduler: postFrame.scheduler,
      lifecycleService: FixedResumeLifecycleService(resume: true),
    );
    addTearDown(() => _tearDownChatCubitWithSessionPersist(cubit, postFrame));
    await cubit.loadWorkspaceData(repo);
    final rel = cubit.state.sessions.single;
    await cubit.requestOpenSession(
      SessionOpenRequest(
        session: rel,
        team: team,
        member: team.members.first,
        repo: repo,
      ),
    );
    await drainPendingAsyncWork();
    await postFrame.flush();
    expect(captured!.lastResumeSessionIds.last, rel.members.single.taskId);
    expect(captured!.lastFixedSessionIds.last, isNull);
  });

  test(
    'openSessionTab started session without CLI descriptor uses session-id',
    () async {
      final tmp = await Directory.systemTemp.createTemp('open_sess_');
      addTearDown(() => _deleteTempDirBestEffort(tmp));
      final repo = SessionRepository(rootDir: tmp.path);
      final team = TeamProfile(
        id: 'tid',
        name: 'TName',
        members: const [TeamMemberConfig(id: 'lid', name: 'team-lead')],
      );
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/wd'),
      ]);
      final session = await repo.createSession(
        workspace.workspaceId,
        sessionTeam: team.id,
        rosterMembers: team.members,

        memberClis: {for (final m in team.members) m.id: CliTool.claude},
      );
      await repo.markSessionLaunched(session.sessionId);

      FakeTerminalSession? captured;
      final postFrame = PostFrameTestHarness();
      final cubit = ChatCubit(
        executableResolver: _testExecutable,
        automationRepository: testAutomationRepository(),
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) {
              captured = FakeTerminalSession(executable: executable);
              return captured!;
            },
        postFrameScheduler: postFrame.scheduler,
        lifecycleService: FixedResumeLifecycleService(resume: false),
      );
      addTearDown(() => _tearDownChatCubitWithSessionPersist(cubit, postFrame));
      await cubit.loadWorkspaceData(repo);
      final rel = cubit.state.sessions.single;
      await cubit.requestOpenSession(
        SessionOpenRequest(
          session: rel,
          team: team,
          member: team.members.first,
          repo: repo,
        ),
      );
      await drainPendingAsyncWork();
      await postFrame.flush();
      expect(captured!.lastResumeSessionIds.last, isNull);
      expect(captured!.lastFixedSessionIds.last, rel.members.single.taskId);
    },
  );

  test(
    'openSessionTab passes session additionalDirectories to connect',
    () async {
      final tmp = await Directory.systemTemp.createTemp('open_sess_');
      addTearDown(() => _deleteTempDirBestEffort(tmp));
      final repo = SessionRepository(rootDir: tmp.path);
      final team = TeamProfile(
        id: 'tid',
        name: 'TName',
        members: const [TeamMemberConfig(id: 'lid', name: 'team-lead')],
      );
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/root'),
        WorkspaceFolder(path: '/extra'),
      ]);
      await repo.createSession(
        workspace.workspaceId,
        sessionTeam: team.id,
        rosterMembers: team.members,

        memberClis: {for (final m in team.members) m.id: CliTool.claude},
      );
      FakeTerminalSession? captured;
      final postFrame = PostFrameTestHarness();
      final cubit = ChatCubit(
        executableResolver: _testExecutable,
        automationRepository: testAutomationRepository(),
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) {
              captured = FakeTerminalSession(executable: executable);
              return captured!;
            },
        postFrameScheduler: postFrame.scheduler,
      );
      addTearDown(() => _tearDownChatCubitWithSessionPersist(cubit, postFrame));
      await cubit.loadWorkspaceData(repo);
      final rel = cubit.state.sessions.single;
      await cubit.requestOpenSession(
        SessionOpenRequest(
          session: rel,
          team: team,
          member: team.members.first,
          repo: repo,
        ),
      );
      await drainPendingAsyncWork();
      await postFrame.flush();
      expect(captured!.lastAdditionalDirectoriesLists.last, ['/extra']);
    },
  );

  test(
    'ensureSession uses binding.cli over live profile and replaces stale shell',
    () async {
      final tmp = await Directory.systemTemp.createTemp('ensure_cli_lock_');
      addTearDown(() => _deleteTempDirBestEffort(tmp));
      final repo = SessionRepository(rootDir: tmp.path);
      final liveTeam = TeamProfile(
        id: 't1',
        name: 'Team',
        cli: CliTool.cursor,
        teamMode: TeamMode.mixed,
        members: const [
          TeamMemberConfig(id: 'team-lead', name: 'Lead', cli: CliTool.cursor),
        ],
      );
      final workspace = await repo.createWorkspace([
        const WorkspaceFolder(path: '/w'),
      ]);
      final session = await repo.createSession(
        workspace.workspaceId,
        sessionTeam: liveTeam.id,
        rosterMembers: liveTeam.members,
        memberClis: {'team-lead': CliTool.claude},
      );
      expect(session.bindingFor('team-lead')?.cli, CliTool.claude);

      final postFrame = PostFrameTestHarness();
      final cubit = ChatCubit(
        executableResolver: () => 'fallback',
        cliExecutableResolver: (cli) => 'bin-${cli.value}',
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                FakeTerminalSession(
                  executable: executable,
                  scrollbackLines: scrollbackLines,
                ),
        postFrameScheduler: postFrame.scheduler,
        lifecycleService: FixedResumeLifecycleService(resume: false),
      );
      addTearDown(() => _tearDownChatCubitWithSessionPersist(cubit, postFrame));
      await cubit.loadWorkspaceData(repo);

      await cubit.requestOpenSession(
        SessionOpenRequest(
          session: session,
          team: liveTeam,
          member: liveTeam.members.first,
          repo: repo,
        ),
      );
      await drainPendingAsyncWork();
      await postFrame.flush();

      final tab = cubit.tabStore.activeTabs.single;
      expect(tab.selectedMemberId, 'team-lead');
      // Simulate a stale idle shell created under the live Cursor profile.
      tab.memberShells['team-lead']?.disconnect();
      final stale = FakeTerminalSession(executable: 'bin-cursor');
      tab.memberShells['team-lead'] = stale;

      final ensured = cubit.ensureSession(liveTeam);
      expect(ensured, isNotNull);
      expect(ensured, isNot(same(stale)));
      expect(ensured!.executable, 'bin-claude');
      expect(tab.memberShells['team-lead']?.executable, 'bin-claude');
    },
  );
}
