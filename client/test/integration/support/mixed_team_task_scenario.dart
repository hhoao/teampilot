import 'package:flutter_test/flutter_test.dart';
import 'package:mock_anthropic/scenario.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
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
import 'mixed_team_idle_busy_assertions.dart';
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
        kickoff: simultaneousKickoff(
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
        kickoff: simultaneousKickoff(
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
        kickoff: simultaneousKickoff(
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
  static Future<void> runTaskCompleteCycle() => run(
        scenarios: taskCompleteMixedClaudeScenarios(),
        kickoff: simultaneousKickoff(
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

      final ctx = MixedTeamScenarioCtx(
        harness: harness,
        cubit: cubit,
        postFrame: postFrame,
        session: session,
      );
      await simultaneousKickoff(
        workerKickoff: taskDispatchWorkerKickoff,
        leaderKickoff: taskDispatchLeaderKickoff,
      )(ctx);
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

  /// L3: local lead + Docker SSH worker claim + `update_task(done)`.
  static Future<void> runTaskCompleteDocker() async {
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
        scenarios: taskCompleteMixedClaudeScenarios(),
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

      final ctx = MixedTeamScenarioCtx(
        harness: harness,
        cubit: cubit,
        postFrame: postFrame,
        session: session,
      );
      await simultaneousKickoff(
        workerKickoff: taskCompleteWorkerKickoff,
        leaderKickoff: taskCompleteLeaderKickoff,
      )(ctx);
      await harness.waitForTaskCompleted(
        workspaceId: session.workspaceId,
        sessionId: session.sessionId,
        title: 'complete-widget',
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

  static MixedTeamKickoff simultaneousKickoff({
    required String workerKickoff,
    required String leaderKickoff,
  }) =>
      (ctx) => ctx.harness.kickoffMembers(
            ctx.cubit,
            postFrame: ctx.postFrame,
            workerKickoff: workerKickoff,
            leaderKickoff: leaderKickoff,
          );

  /// Shared L2 session bootstrap (real Claude PTY + mock Anthropic).
  static Future<void> run({
    required ScenarioRegistry scenarios,
    MixedTeamKickoff? kickoff,
    Future<void> Function(MixedTeamScenarioCtx ctx)? afterReady,
    Future<void> Function(MixedTeamScenarioCtx ctx)? verify,
    bool withPresence = false,
  }) async {
    IntegrationPrerequisites.skipUnlessNativePty();
    final claudePath = IntegrationPrerequisites.requireClaudePath()!;

    final harness = MixedTeamIntegrationHarness(claudePath: claudePath);
    final postFrame = PostFrameTestHarness();
    MemberPresenceCubit? presenceCubit;
    AppSession? session;
    ChatCubit? cubit;
    try {
      await harness.startMockServer(scenarios: scenarios);
      await harness.writeMockProviders();
      final repo = SessionRepository();
      cubit = harness.createCubit(postFrame: postFrame);
      if (withPresence) {
        presenceCubit = MemberPresenceCubit();
        bindMixedTeamPresence(
          chatCubit: cubit,
          presenceCubit: presenceCubit,
        );
      }

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

      final ctx = MixedTeamScenarioCtx(
        harness: harness,
        cubit: cubit,
        postFrame: postFrame,
        session: session,
        presenceCubit: presenceCubit,
      );
      if (afterReady != null) await afterReady(ctx);
      if (kickoff != null) await kickoff(ctx);
      if (verify != null) await verify(ctx);

      expect(cubit.hasTeamBusResources(session.sessionId), isTrue);
    } catch (e, st) {
      await harness.dumpFailureArtifacts(
        workspaceId: session?.workspaceId,
        sessionId: session?.sessionId,
        cubit: cubit,
      );
      Error.throwWithStackTrace(e, st);
    } finally {
      await presenceCubit?.close();
      await harness.dispose();
      await postFrame.flush();
      await drainPendingAsyncWork();
      await Future<void>.delayed(_ptyReleaseDelay);
    }
  }

  static Future<void> _run({
    required ScenarioRegistry scenarios,
    required MixedTeamKickoff kickoff,
    required Future<void> Function(MixedTeamScenarioCtx ctx) verify,
    bool withPresence = false,
  }) =>
      run(
        scenarios: scenarios,
        kickoff: kickoff,
        verify: verify,
        withPresence: withPresence,
      );
}

typedef MixedTeamKickoff = Future<void> Function(MixedTeamScenarioCtx ctx);

final class MixedTeamScenarioCtx {
  const MixedTeamScenarioCtx({
    required this.harness,
    required this.cubit,
    required this.postFrame,
    required this.session,
    this.presenceCubit,
  });

  final MixedTeamIntegrationHarness harness;
  final ChatCubit cubit;
  final PostFrameTestHarness postFrame;
  final AppSession session;
  final MemberPresenceCubit? presenceCubit;
}
