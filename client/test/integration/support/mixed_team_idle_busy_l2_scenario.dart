import 'package:flutter_test/flutter_test.dart';
import 'package:mock_model_gateway/scenarios/task_complete_mixed_claude.dart';
import 'package:mock_model_gateway/scenarios/task_dispatch_mixed_claude.dart';
import 'package:teampilot/models/member_presence.dart';

import 'bus_roster_assertions.dart';
import 'mixed_team_idle_busy_assertions.dart';
import 'mixed_team_integration_harness.dart';
import 'mixed_team_task_scenario.dart';
import 'session_idle_busy_harness.dart';

/// L2 idle/busy: real Claude PTY + ChatCubit.busySessionIds + MemberPresence.
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
        ctx.presenceCubit!.memberPresenceFor(kWorkerMember.id).availability,
        MemberAvailability.idle,
      );
      expect(
        ctx.presenceCubit!.memberPresenceFor(kLeadMember.id).availability,
        MemberAvailability.idle,
      );
    },
  );

  /// Worker kickoff parks on `wait_for_message` (task-dispatch mock turn 2).
  static Future<void> runWorkerKickoffThenSessionIdle() =>
      MixedTeamTaskScenario.run(
        scenarios: taskDispatchWorkerParkOnlyScenarios(),
        withPresence: true,
        afterReady: (ctx) async {
          await ctx.harness.ensureWorkerParkedOnWait(
            ctx.cubit,
            sessionId: ctx.session.sessionId,
            postFrame: ctx.postFrame,
            workerKickoff: taskDispatchWorkerKickoff,
            timeout: const Duration(seconds: 120),
          );

          await tickIdleAndPresence(
            cubit: ctx.cubit,
            presenceCubit: ctx.presenceCubit!,
          );
          final bus = ctx.harness.tabBus(ctx.session.sessionId)!;
          expect(bus.isWaitingForMessage(kWorkerMember.id), isTrue);
          expect(bus.isMemberInTurn(kWorkerMember.id), isFalse);
          expect(
            ctx.presenceCubit!.memberPresenceFor(kWorkerMember.id).availability,
            MemberAvailability.idle,
          );
          // Worker idle-notify may doorbell an idle-at-prompt leader.
          expect(
            ctx.presenceCubit!.memberPresenceFor(kLeadMember.id).availability,
            anyOf(MemberAvailability.idle, MemberAvailability.working),
          );
        },
      );

  /// After claim + `update_task(done)`, session returns to idle.
  static Future<void>
  runSessionIdleAfterTaskComplete() => MixedTeamTaskScenario.run(
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
      final bus = ctx.harness.tabBus(ctx.session.sessionId)!;
      // Worker idle-notify may doorbell leader; drain unread before settling.
      await bus.readMessages('team-lead', markRead: true, unreadOnly: true);
      final tab = ctx.cubit.tabStore.openTabBySessionId(ctx.session.sessionId);
      if (tab != null) {
        for (final shell in tab.memberShells.values) {
          simulateFingerprintQuietGap(shell);
        }
      }
      await waitUntilSessionIdle(
        cubit: ctx.cubit,
        sessionId: ctx.session.sessionId,
        timeout: const Duration(seconds: 180),
      );
      expectSessionIdle(ctx.cubit, ctx.session.sessionId);
      await waitUntilMemberAvailability(
        presenceCubit: ctx.presenceCubit!,
        cubit: ctx.cubit,
        memberId: kWorkerMember.id,
        availability: MemberAvailability.idle,
      );
      await waitUntilMemberAvailability(
        presenceCubit: ctx.presenceCubit!,
        cubit: ctx.cubit,
        memberId: kLeadMember.id,
        availability: MemberAvailability.idle,
      );
    },
  );
}
