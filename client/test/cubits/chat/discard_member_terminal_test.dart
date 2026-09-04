import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/session_open_request.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/expert_hub/expert_member_materializer.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';
import 'package:teampilot/utils/team/team_member_naming.dart';

import '../../support/fake_terminal_session.dart';
import '../../support/fixed_resume_lifecycle_service.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('discardMemberTerminal removes the shell and marks it reclaimed', () async {
    final team = await ExpertMemberMaterializer.attachMaterializedMembers(
      TeamProfile(
        id: LaunchProfileProvisioner.defaultNativeTeamId,
        name: 'Team',
        roster: TeamMemberNaming.defaultRoster(),
      ),
    );
    final tmp = await Directory.systemTemp.createTemp('discard_member_');
    addTearDown(() => deleteTempDirBestEffort(tmp));
    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([
      const WorkspaceFolder(path: '/work'),
    ]);
    final session = (await repo.createSession(
      workspace.workspaceId,
      sessionTeam: team.id,
      rosterMembers: team.members,
      memberClis: {for (final m in team.members) m.id: CliTool.claude},
    )).session;

    final postFrame = PostFrameTestHarness();
    final cubit = ChatCubit(
      executableResolver: () => 'flashskyai',
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
    addTearDown(() => tearDownChatCubitWithSessionPersist(cubit, postFrame));
    await cubit.loadWorkspaceData(repo);
    cubit.activateWorkspaceTab(
      workspaceTabKey: workspace.workspaceId,
      scopeSessionsToSelectedTeam: false,
    );
    await cubit.requestOpenSession(
      SessionOpenRequest(
        session: session,
        team: team,
        member: team.members.first,
        repo: repo,
      ),
    );
    await drainPendingAsyncWork();
    await postFrame.flush();

    final tab = cubit.tabStore.openTabBySessionId(session.sessionId)!;
    final memberId = team.members.first.id;

    final shell = FakeTerminalSession(executable: 'bin');
    shell.connect(workingDirectory: '/work');
    tab.memberShells[memberId] = shell;
    tab.selectedMemberId = memberId;
    expect(shell.isRunning, isTrue);

    // The workbench body listens to the pod; the discard must notify it so
    // the dead terminal swaps to the reclaimed placeholder instead of
    // staying mounted as an unresponsive surface.
    final pod = cubit.podRuntime(session.sessionId)!;
    var podNotifications = 0;
    pod.addListener(() => podNotifications++);

    cubit.discardMemberTerminal(session.sessionId, memberId);

    expect(tab.memberShells.containsKey(memberId), isFalse,
      reason: 'reclaimed shell is removed from the live member shells');
    expect(tab.reclaimedMemberIds, contains(memberId));
    expect(shell.isRunning, isFalse, reason: 'shell transport is disconnected');
    expect(podNotifications, greaterThan(0),
      reason: 'pod listeners re-read terminal liveness after discard');
  });

  test('discardMemberTerminal is a no-op when the shell is not running', () async {
    final team = await ExpertMemberMaterializer.attachMaterializedMembers(
      TeamProfile(
        id: LaunchProfileProvisioner.defaultNativeTeamId,
        name: 'Team',
        roster: TeamMemberNaming.defaultRoster(),
      ),
    );
    final tmp = await Directory.systemTemp.createTemp('discard_member_');
    addTearDown(() => deleteTempDirBestEffort(tmp));
    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([
      const WorkspaceFolder(path: '/work'),
    ]);
    final session = (await repo.createSession(
      workspace.workspaceId,
      sessionTeam: team.id,
      rosterMembers: team.members,
      memberClis: {for (final m in team.members) m.id: CliTool.claude},
    )).session;

    final postFrame = PostFrameTestHarness();
    final cubit = ChatCubit(
      executableResolver: () => 'flashskyai',
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
    addTearDown(() => tearDownChatCubitWithSessionPersist(cubit, postFrame));
    await cubit.loadWorkspaceData(repo);
    cubit.activateWorkspaceTab(
      workspaceTabKey: workspace.workspaceId,
      scopeSessionsToSelectedTeam: false,
    );
    await cubit.requestOpenSession(
      SessionOpenRequest(
        session: session,
        team: team,
        member: team.members.first,
        repo: repo,
      ),
    );
    await drainPendingAsyncWork();
    await postFrame.flush();

    final tab = cubit.tabStore.openTabBySessionId(session.sessionId)!;
    final memberId = team.members.first.id;

    // A shell that is present but NOT running (disconnected) is not reclaimable.
    final idleShell = FakeTerminalSession(executable: 'bin');
    expect(idleShell.isRunning, isFalse);
    tab.memberShells[memberId] = idleShell;
    tab.selectedMemberId = memberId;

    cubit.discardMemberTerminal(session.sessionId, memberId);

    expect(tab.reclaimedMemberIds, isNot(contains(memberId)),
      reason: 'a non-running shell is nothing to reclaim → no-op');
    expect(tab.memberShells[memberId], same(idleShell),
      reason: 'shell stays in place when not reclaimed');
  });
}
