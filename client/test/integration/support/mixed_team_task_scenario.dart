import 'package:flutter_test/flutter_test.dart';
import 'package:mock_anthropic/scenario.dart';
import 'package:mock_anthropic/scenarios/doorbell_dispatch_mixed_claude.dart';
import 'package:mock_anthropic/scenarios/mail_priority_mixed_claude.dart';
import 'package:mock_anthropic/scenarios/task_complete_mixed_claude.dart';
import 'package:mock_anthropic/scenarios/task_dispatch_mixed_claude.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/post_frame_test_harness.dart';
import 'bus_mail_assertions.dart';
import 'bus_roster_assertions.dart';
import 'bus_task_assertions.dart';
import 'docker_ssh_server.dart';
import 'integration_prerequisites.dart';
import 'mixed_team_integration_harness.dart';

/// L2 mixed-team scenarios: real Claude PTY + mock Anthropic + bus persistence.
abstract final class MixedTeamTaskScenario {
  static const _ptyReleaseDelay = Duration(seconds: 2);

  /// Leader `add_tasks` → worker `wait_for_message` auto-claim.
  ///
  /// Uses simultaneous kickoff: worker SSE park and leader dispatch overlap
  /// (observed in L2 logs); [kickoffWorkerParkedThenLeader] times out because
  /// the worker mock turn completes before MCP opens the wait stream.
  static Future<void> runTaskDispatch() => _run(
        scenarios: taskDispatchMixedClaudeScenarios(),
        kickoff: _Kickoff.simultaneous(
          workerKickoff: taskDispatchWorkerKickoff,
          leaderKickoff: taskDispatchLeaderKickoff,
        ),
        verify: (ctx) async {
          await ctx.harness.waitForTaskDispatched(
            workspaceId: ctx.session.workspaceId,
            sessionId: ctx.session.sessionId,
            title: 'ship-widget',
          );
        },
      );

  /// Task enqueued + urgent mail: worker must consume mail before claiming.
  static Future<void> runMailPriorityOverTask() => _run(
        scenarios: mailPriorityMixedClaudeScenarios(),
        kickoff: _Kickoff.simultaneous(
          workerKickoff: mailPriorityWorkerKickoff,
          leaderKickoff: mailPriorityLeaderKickoff,
        ),
        verify: (ctx) async {
          const mailContent = 'urgent: pause work';
          const taskTitle = 'orphan-task';

          await ctx.harness.waitForWorkerMail(
            workspaceId: ctx.session.workspaceId,
            sessionId: ctx.session.sessionId,
            fromMemberId: kLeadMember.id,
            content: mailContent,
          );

          final root = AppStorage.paths.basePath;
          final mailRows = await readBusMailLines(
            teampilotRoot: root,
            workspaceId: ctx.session.workspaceId,
            sessionId: ctx.session.sessionId,
            memberId: kWorkerMember.id,
          );
          final mailAt = mailCreatedAtForContent(
            mailRows,
            fromMemberId: kLeadMember.id,
            content: mailContent,
          );
          expect(mailAt, isNotNull);

          await ctx.harness.waitForLeaderMail(
            workspaceId: ctx.session.workspaceId,
            sessionId: ctx.session.sessionId,
            fromMemberId: kWorkerMember.id,
            content: 'copy that',
          );

          await ctx.harness.waitForTaskDispatched(
            workspaceId: ctx.session.workspaceId,
            sessionId: ctx.session.sessionId,
            title: taskTitle,
          );

          final tasksFinal = await readBusTaskEvents(
            teampilotRoot: root,
            workspaceId: ctx.session.workspaceId,
            sessionId: ctx.session.sessionId,
          );
          final claimAt = claimTimestampForTitle(
            tasksFinal,
            taskTitle,
            assignee: kWorkerMember.id,
          );
          expect(claimAt, isNotNull);
          expectClaimAfterMail(
            mailCreatedAt: mailAt!,
            claimAt: claimAt!,
            title: taskTitle,
          );
        },
      );

  /// Worker at prompt (no initial wait); leader `add_tasks` doorbells → claim.
  static Future<void> runDoorbellDispatch() => _run(
        scenarios: doorbellDispatchMixedClaudeScenarios(),
        kickoff: _Kickoff.simultaneous(
          workerKickoff: doorbellDispatchWorkerKickoff,
          leaderKickoff: doorbellDispatchLeaderKickoff,
        ),
        verify: (ctx) async {
          final snap = memberSnapshot(
            ctx.harness.tabBus(ctx.session.sessionId),
            kWorkerMember.id,
          );
          expect(
            snap?.activity.name,
            anyOf('turnDoneReady', 'active', 'turnDoneBusWait'),
          );

          await ctx.harness.waitForTaskDispatched(
            workspaceId: ctx.session.workspaceId,
            sessionId: ctx.session.sessionId,
            title: 'doorbell-widget',
          );
        },
      );

  /// Worker claims via `wait_for_message`, reports `update_task(done)`; jsonl proof.
  static Future<void> runTaskCompleteCycle() => _run(
        scenarios: taskCompleteMixedClaudeScenarios(),
        kickoff: _Kickoff.simultaneous(
          workerKickoff: taskCompleteWorkerKickoff,
          leaderKickoff: taskCompleteLeaderKickoff,
        ),
        verify: (ctx) async {
          const title = 'complete-widget';

          await ctx.harness.waitForTaskDispatched(
            workspaceId: ctx.session.workspaceId,
            sessionId: ctx.session.sessionId,
            title: title,
          );
          await ctx.harness.waitForTaskCompleted(
            workspaceId: ctx.session.workspaceId,
            sessionId: ctx.session.sessionId,
            title: title,
          );

          final events = await readBusTaskEvents(
            teampilotRoot: AppStorage.paths.basePath,
            workspaceId: ctx.session.workspaceId,
            sessionId: ctx.session.sessionId,
          );
          final claimAt = claimTimestampForTitle(
            events,
            title,
            assignee: kWorkerMember.id,
          );
          final doneAt = doneTimestampForTitle(events, title);
          expect(claimAt, isNotNull);
          expect(doneAt, isNotNull);
          expect(doneAt! > claimAt!, isTrue);
        },
      );

  /// L3: local lead + Docker SSH worker task dispatch.
  static Future<void> runTaskDispatchDocker() async {
    if (!await DockerSshServer.isDockerAvailable()) {
      markTestSkipped('Docker is not available');
    }
    IntegrationPrerequisites.skipUnlessNativePty();
    final claudePath = IntegrationPrerequisites.requireClaudePath()!;

    final harness = MixedTeamIntegrationHarness(claudePath: claudePath);
    final postFrame = PostFrameTestHarness();
    MixedTeamDockerRemote? remote;
    AppSession? session;
    ChatCubit? cubit;
    try {
      remote = await MixedTeamDockerRemote.start();
      await harness.startMockServer(
        scenarios: taskDispatchMixedClaudeScenarios(),
        exposeToDocker: true,
      );
      await harness.writeMockProviders(
        workerBaseUrl:
            'http://${DockerSshServer.hostGatewayHostname}:${harness.mockPort}',
      );
      await harness.verifyMockReachableFromDocker(remote);

      final repo = SessionRepository();
      cubit = harness.createDockerCubit(postFrame: postFrame, remote: remote);

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

      final ctx = _ScenarioCtx(
        harness: harness,
        cubit: cubit,
        postFrame: postFrame,
        session: session,
      );
      await _Kickoff.simultaneous(
        workerKickoff: taskDispatchWorkerKickoff,
        leaderKickoff: taskDispatchLeaderKickoff,
      ).apply(ctx);
      await harness.waitForTaskDispatched(
        workspaceId: session.workspaceId,
        sessionId: session.sessionId,
        title: 'ship-widget',
        timeout: const Duration(seconds: 120),
      );

      expect(cubit.hasTeamBusResources(session.sessionId), isTrue);
    } catch (e, st) {
      await harness.dumpFailureArtifacts(
        workspaceId: session?.workspaceId,
        sessionId: session?.sessionId,
        cubit: cubit,
      );
      Error.throwWithStackTrace(e, st);
    } finally {
      await remote?.dispose();
      await harness.dispose();
      await postFrame.flush();
      await drainPendingAsyncWork();
      await Future<void>.delayed(_ptyReleaseDelay);
    }
  }

  static Future<void> _run({
    required ScenarioRegistry scenarios,
    required _Kickoff kickoff,
    required Future<void> Function(_ScenarioCtx ctx) verify,
  }) async {
    IntegrationPrerequisites.skipUnlessNativePty();
    final claudePath = IntegrationPrerequisites.requireClaudePath()!;

    final harness = MixedTeamIntegrationHarness(claudePath: claudePath);
    final postFrame = PostFrameTestHarness();
    AppSession? session;
    ChatCubit? cubit;
    try {
      await harness.startMockServer(scenarios: scenarios);
      await harness.writeMockProviders();
      final repo = SessionRepository();
      cubit = harness.createCubit(postFrame: postFrame);

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

      final ctx = _ScenarioCtx(
        harness: harness,
        cubit: cubit,
        postFrame: postFrame,
        session: session,
      );
      await kickoff.apply(ctx);
      await verify(ctx);

      expect(cubit.hasTeamBusResources(session.sessionId), isTrue);
    } catch (e, st) {
      await harness.dumpFailureArtifacts(
        workspaceId: session?.workspaceId,
        sessionId: session?.sessionId,
        cubit: cubit,
      );
      Error.throwWithStackTrace(e, st);
    } finally {
      await harness.dispose();
      await postFrame.flush();
      await drainPendingAsyncWork();
      await Future<void>.delayed(_ptyReleaseDelay);
    }
  }
}

final class _ScenarioCtx {
  const _ScenarioCtx({
    required this.harness,
    required this.cubit,
    required this.postFrame,
    required this.session,
  });

  final MixedTeamIntegrationHarness harness;
  final ChatCubit cubit;
  final PostFrameTestHarness postFrame;
  final AppSession session;
}

sealed class _Kickoff {
  const _Kickoff();

  factory _Kickoff.simultaneous({
    required String workerKickoff,
    required String leaderKickoff,
  }) = _SimultaneousKickoff;

  Future<void> apply(_ScenarioCtx ctx);
}

final class _SimultaneousKickoff extends _Kickoff {
  const _SimultaneousKickoff({
    required this.workerKickoff,
    required this.leaderKickoff,
  });

  final String workerKickoff;
  final String leaderKickoff;

  @override
  Future<void> apply(_ScenarioCtx ctx) => ctx.harness.kickoffMembers(
        ctx.cubit,
        postFrame: ctx.postFrame,
        workerKickoff: workerKickoff,
        leaderKickoff: leaderKickoff,
      );
}
