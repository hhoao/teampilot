import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/post_frame_test_harness.dart';
import 'docker_ssh_server.dart';
import 'integration_prerequisites.dart';
import 'mixed_team_integration_harness.dart';

/// Shared L2/L3 mixed-team ping/pong scenarios (ChatCubit + mock Anthropic).
abstract final class MixedTeamPingPongScenario {
  static const _ptyReleaseDelay = Duration(seconds: 2);

  /// L2: two local Claude PTYs exchange ping/pong via the production launch path.
  static Future<void> runLocal() async {
    IntegrationPrerequisites.skipUnlessNativePty();
    final claudePath = IntegrationPrerequisites.requireClaudePath()!;

    final harness = MixedTeamIntegrationHarness(claudePath: claudePath);
    final postFrame = PostFrameTestHarness();
    AppSession? session;
    try {
      await harness.startMockServer();
      await harness.writeMockProviders();
      final repo = SessionRepository();
      final cubit = harness.createCubit(postFrame: postFrame);

      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: AppStorage.cwd),
      ]);
      session = await repo.createSession(
        workspace.workspaceId,
        sessionTeam: kItMixedClaudeTeam.id,
        rosterMembers: kItMixedClaudeTeam.members,
      );

      await cubit.requestOpenSession(
        SessionOpenRequest(
          session: session,
          team: kItMixedClaudeTeam,
          member: kLeadMember,
          repo: repo,
          connectImmediately: true,
        ),
      );
      await drainPendingAsyncWork();
      await postFrame.flush();
      await harness.waitUntilMembersReady(
        cubit,
        [kLeadMember.id, kWorkerMember.id],
      );
      await harness.kickoffMembers(cubit, postFrame: postFrame);
      await harness.waitForPingPong(
        workspaceId: session.workspaceId,
        sessionId: session.sessionId,
      );

      expect(cubit.hasTeamBusResources(session.sessionId), isTrue);
    } catch (e, st) {
      await harness.dumpFailureArtifacts(
        workspaceId: session?.workspaceId,
        sessionId: session?.sessionId,
      );
      Error.throwWithStackTrace(e, st);
    } finally {
      await _dispose(harness: harness, postFrame: postFrame);
    }
  }

  /// L3: local lead + Docker SSH worker, including remote preflight.
  static Future<void> runDocker() async {
    if (!await DockerSshServer.isDockerAvailable()) {
      markTestSkipped('Docker is not available');
    }
    IntegrationPrerequisites.skipUnlessNativePty();
    final claudePath = IntegrationPrerequisites.requireClaudePath()!;

    final harness = MixedTeamIntegrationHarness(claudePath: claudePath);
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

      final repo = SessionRepository();
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: AppStorage.cwd),
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
      session = (await repo.loadSessions()).firstWhere(
        (s) => s.sessionId == session!.sessionId,
      );

      expect(session.memberTargets[kLeadMember.id], 'local');

      await cubit.requestOpenSession(
        SessionOpenRequest(
          session: session,
          team: kItMixedClaudeTeam,
          member: kLeadMember,
          repo: repo,
          connectImmediately: true,
        ),
      );
      await drainPendingAsyncWork();
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
      await remote?.dispose();
      await _dispose(harness: harness, postFrame: postFrame);
    }
  }

  static Future<void> _dispose({
    required MixedTeamIntegrationHarness harness,
    required PostFrameTestHarness postFrame,
  }) async {
    await harness.dispose();
    await postFrame.flush();
    await drainPendingAsyncWork();
    // Let Claude PTY children release config dir handles before tearDown.
    await Future<void>.delayed(_ptyReleaseDelay);
  }
}
