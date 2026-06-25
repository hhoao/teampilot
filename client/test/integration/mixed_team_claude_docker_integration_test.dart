@Tags(['integration'])
@Timeout(Duration(minutes: 6))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../support/post_frame_test_harness.dart';
import 'support/docker_ssh_server.dart';
import 'support/mixed_team_integration_harness.dart';

/// Local team-lead + Docker SSH worker, full ChatCubit launch path including
/// remote preflight (Node bootstrap + Claude install) and bus ping/pong.
///
/// Run from `client/` (Docker daemon, outbound network, local `claude` on PATH,
/// `libflutter_pty.so` after `flutter build linux --debug`):
/// ```bash
/// flutter test test/integration/mixed_team_claude_docker_integration_test.dart --tags integration
/// ```
void main() {
  setUp(() {
    HttpOverrides.global = null;
    setUpTestAppStorage();
  });
  tearDown(tearDownTestAppStorage);

  test(
    'local lead + docker worker exchange ping/pong via ChatCubit',
    () async {
      if (!await DockerSshServer.isDockerAvailable()) {
        markTestSkipped('Docker is not available');
      }
      if (!MixedTeamIntegrationHarness.nativePtyAvailable) {
        markTestSkipped('Requires libflutter_pty.so');
      }
      final claudePath = MixedTeamIntegrationHarness.resolveClaudePath();
      if (claudePath == null) {
        markTestSkipped('claude not on PATH');
      }

      final harness = MixedTeamIntegrationHarness(claudePath: claudePath!);
      final postFrame = PostFrameTestHarness();
      MixedTeamDockerRemote? remote;
      AppSession? session;
      try {
        remote = await MixedTeamDockerRemote.start();
        await harness.startMockServer(exposeToDocker: true);
        await harness.writeMockProviders(
          workerBaseUrl:
              'http://${DockerSshServer.hostGatewayHostname}:${harness.mockPort}',
        );
        await harness.verifyMockReachableFromDocker(remote);

        final cubit = harness.createDockerCubit(
          postFrame: postFrame,
          remote: remote,
        );
        harness.cubit = cubit;

        final repo = SessionRepository();
        final localPath = AppStorage.cwd;
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: localPath),
          WorkspaceFolder(
            path: MixedTeamDockerRemote.remoteWorkspacePath,
            targetId: remote.sshTargetId,
          ),
        ]);
        await repo.updateWorkspaceMemberTargets(
          workspace.workspaceId,
          kItMixedClaudeTeam.id,
          targets: {
            kLeadMember.id: 'local',
            kWorkerMember.id: remote.sshTargetId,
          },
        );
        session = await repo.createSession(
          workspace.workspaceId,
          sessionTeam: kItMixedClaudeTeam.id,
          rosterMembers: kItMixedClaudeTeam.members,
        );
        await repo.setMemberTarget(
          session.sessionId,
          kLeadMember.id,
          'local',
        );
        await repo.setMemberTarget(
          session.sessionId,
          kWorkerMember.id,
          remote.sshTargetId,
        );
        final reloaded = (await repo.loadSessions()).firstWhere(
          (s) => s.sessionId == session!.sessionId,
        );
        session = reloaded;

        expect(reloaded.memberTargets[kLeadMember.id], 'local');

        await cubit.openSessionTab(
          session,
          team: kItMixedClaudeTeam,
          member: kLeadMember,
          repo: repo,
          connectImmediately: true,
        );
        await postFrame.flush();
        await harness.waitUntilDockerMembersReady(
          cubit,
          [kLeadMember.id, kWorkerMember.id],
        );
        await harness.kickoffAndWaitForPingPong(
          cubit: cubit,
          workspaceId: session.workspaceId,
          sessionId: session.sessionId,
          postFrame: postFrame,
        );

        expect(cubit.hasTeamBusResources(session.sessionId), isTrue);
      } catch (e, st) {
        await harness.dumpFailureArtifacts(
          workspaceId: session?.workspaceId,
          sessionId: session?.sessionId,
        );
        Error.throwWithStackTrace(e, st);
      } finally {
        await harness.dispose();
        await remote?.dispose();
        await postFrame.flush();
        await drainPendingAsyncWork();
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    },
  );
}
