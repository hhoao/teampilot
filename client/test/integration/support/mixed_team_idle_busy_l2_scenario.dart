import 'package:flutter_test/flutter_test.dart';
import 'package:mock_anthropic/scenarios/task_complete_mixed_claude.dart';
import 'package:mock_anthropic/scenarios/task_dispatch_mixed_claude.dart';
import 'package:teampilot/models/member_presence.dart';

import 'mixed_team_idle_busy_assertions.dart';
import 'mixed_team_integration_harness.dart';
import 'mixed_team_task_scenario.dart';

/// L2 idle/busy: real Claude PTY + ChatCubit.workingSessionIds + MemberPresence.
abstract final class MixedTeamIdleBusyL2Scenario {
  /// Mixed session idle at prompt on real PTYs (no false-positive from spinner).
  static Future<void> runSessionIdleAtPrompt() => MixedTeamTaskScenario.run(
        scenarios: taskDispatchMixedClaudeScenarios(),
        withPresence: true,
        afterReady: (ctx) async {
          await waitUntilWorkerIdleOnBus(
            bus: ctx.harness.tabBus(ctx.session.sessionId),
            workspaceId: ctx.session.workspaceId,
            sessionId: ctx.session.sessionId,
            memberId: kLeadMember.id,
          );
          await waitUntilWorkerIdleOnBus(
            bus: ctx.harness.tabBus(ctx.session.sessionId),
            workspaceId: ctx.session.workspaceId,
            sessionId: ctx.session.sessionId,
          );

          await tickIdleAndPresence(
            cubit: ctx.cubit,
            presenceCubit: ctx.presenceCubit!,
          );
          expectSessionIdle(ctx.cubit, ctx.session.sessionId);
          expect(
            ctx.presenceCubit!.memberPresenceFor(kWorkerMember.id).workload,
            MemberWorkload.idle,
          );
          expect(
            ctx.presenceCubit!.memberPresenceFor(kLeadMember.id).workload,
            MemberWorkload.idle,
          );
        },
      );

  /// Worker kickoff → bus idle → session idle (L2 PTY, roster/jsonl sync).
  static Future<void> runWorkerKickoffThenSessionIdle() =>
      MixedTeamTaskScenario.run(
        scenarios: taskDispatchMixedClaudeScenarios(),
        withPresence: true,
        afterReady: (ctx) async {
          await ctx.harness.submitWorkerKickoffOnly(
            ctx.cubit,
            kickoff: taskDispatchWorkerKickoff,
          );
          await waitUntilWorkerIdleOnBus(
            bus: ctx.harness.tabBus(ctx.session.sessionId),
            workspaceId: ctx.session.workspaceId,
            sessionId: ctx.session.sessionId,
          );

          await tickIdleAndPresence(
            cubit: ctx.cubit,
            presenceCubit: ctx.presenceCubit!,
          );
          expectSessionIdle(ctx.cubit, ctx.session.sessionId);
          expect(
            ctx.presenceCubit!.memberPresenceFor(kWorkerMember.id).workload,
            MemberWorkload.idle,
          );
        },
      );

  /// After claim + `update_task(done)`, session returns to idle.
  static Future<void> runSessionIdleAfterTaskComplete() =>
      MixedTeamTaskScenario.run(
        scenarios: taskCompleteMixedClaudeScenarios(),
        withPresence: true,
        kickoff: MixedTeamTaskScenario.simultaneousKickoff(
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

          await waitUntilWorkerIdleOnBus(
            bus: ctx.harness.tabBus(ctx.session.sessionId),
            workspaceId: ctx.session.workspaceId,
            sessionId: ctx.session.sessionId,
          );

          await waitUntilSessionIdle(
            cubit: ctx.cubit,
            sessionId: ctx.session.sessionId,
          );
          await waitUntilMemberWorkload(
            presenceCubit: ctx.presenceCubit!,
            memberId: kWorkerMember.id,
            workload: MemberWorkload.idle,
          );
        },
      );
}
