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
import '../../support/test_runtime_context.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test(
    'disconnectMemberShell targets arbitrary session member, not only active',
    () async {
      final team = await ExpertMemberMaterializer.attachMaterializedMembers(
        TeamProfile(
          id: LaunchProfileProvisioner.defaultNativeTeamId,
          name: 'Team',
          roster: TeamMemberNaming.defaultRoster(),
        ),
      );
      final tmp = await Directory.systemTemp.createTemp('disconnect_member_');
      addTearDown(() => deleteTempDirBestEffort(tmp));
      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        const WorkspaceFolder(path: '/work'),
      ]);
      final sessionA = (await repo.createSession(
        workspace.workspaceId,
        sessionTeam: team.id,
        rosterMembers: team.members,
        memberClis: {for (final m in team.members) m.id: CliTool.claude},
      )).session;
      final sessionB = (await repo.createSession(
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
          session: sessionA,
          team: team,
          member: team.members.first,
          repo: repo,
        ),
      );
      await cubit.requestOpenSession(
        SessionOpenRequest(
          session: sessionB,
          team: team,
          member: team.members.first,
          repo: repo,
        ),
      );
      await drainPendingAsyncWork();
      await postFrame.flush();

      final tabA = cubit.tabStore.openTabBySessionId(sessionA.sessionId)!;
      final tabB = cubit.tabStore.openTabBySessionId(sessionB.sessionId)!;
      final memberId = team.members.first.id;

      final shellA = FakeTerminalSession(executable: 'bin-a');
      final shellB = FakeTerminalSession(executable: 'bin-b');
      shellA.connect(workingDirectory: '/work');
      shellB.connect(workingDirectory: '/work');
      tabA.memberShells[memberId] = shellA;
      tabB.memberShells[memberId] = shellB;
      tabA.selectedMemberId = memberId;
      tabB.selectedMemberId = memberId;

      // A is the first open tab, so the active-tab fallback resolves to A;
      // Resource Manager kill must still hit B.
      expect(cubit.activeTab?.info.id, sessionA.sessionId);
      expect(shellA.isRunning, isTrue);
      expect(shellB.isRunning, isTrue);

      cubit.disconnectMemberShell(sessionB.sessionId, memberId);

      expect(shellB.isRunning, isFalse);
      expect(shellA.isRunning, isTrue);
      expect(tabB.memberShells.containsKey(memberId), isTrue);
    },
  );
}
