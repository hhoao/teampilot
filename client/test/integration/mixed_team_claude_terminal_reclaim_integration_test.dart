@Tags(['integration', 'linux-pty'])
@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mock_model_gateway/scenarios/task_dispatch_mixed_claude.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';

import '../support/post_frame_test_harness.dart';
import 'support/integration_test_setup.dart';
import 'support/mixed_team_idle_busy_assertions.dart';
import 'support/mixed_team_integration_harness.dart';
import 'support/mixed_team_task_scenario.dart';

/// Real-CLI coverage for idle reclaim: boot a real mixed Claude team on real
/// PTYs, drive the reclaim watch (real 1s timer, 2s threshold) and observe the
/// idle worker's actual PTY being torn down while the lead stays up.
void main() {
  setUp(setUpIntegrationAppStorage);
  tearDown(tearDownIntegrationAppStorage);

  test(
    'real mixed session: idle worker PTY is reclaimed, lead stays',
    () async {
      await MixedTeamTaskScenario.run(
        scenarios: taskDispatchMixedClaudeScenarios(),
        reclaimIdleTerminalsEnabled: () => true,
        reclaimIdleTerminalAfterSeconds: () => 2,
        afterReady: (ctx) async {
          final bus = ctx.harness.tabBus(ctx.session.sessionId);
          final tab = ctx.cubit.tabStore.openTabBySessionId(
            ctx.session.sessionId,
          )!;

          // The lead is protected and stays running; confirm it is idle.
          await waitUntilWorkerIdleOnBus(
            bus: bus,
            workspaceId: ctx.session.workspaceId,
            sessionId: ctx.session.sessionId,
            memberId: kLeadMember.id,
          );

          // The worker may already be reclaimed (the 2s threshold fires once it
          // idles, possibly during the boot settle) or may still be settling —
          // either way, poll until reclaim is recorded and no worker PTY is
          // running. UI member selection (e.g. the harness settle loop) can
          // lazily restore a disconnected shell stub via `ensureMemberTerminalForView`,
          // so assert the reclaim semantics (marked reclaimed + no live PTY)
          // instead of an empty `memberShells` map.
          await waitUntil(
            () {
              final shell = tab.memberShells[kWorkerMember.id];
              return tab.reclaimedMemberIds.contains(kWorkerMember.id) &&
                  (shell == null || (!shell.isRunning && !shell.isConnecting));
            },
            timeout: const Duration(seconds: 20),
            step: const Duration(milliseconds: 500),
          );

          expect(
            bus!.memberById(kWorkerMember.id)!.lifecycle,
            MemberLifecycle.declared,
            reason: 'reclaimed worker must reset to declared on the real bus',
          );
          expect(tab.reclaimedMemberIds, contains(kWorkerMember.id));
          expect(
            tab.memberShells.containsKey(kLeadMember.id),
            isTrue,
            reason: 'the lead terminal is protected from idle reclaim',
          );
        },
      );
    },
  );
}
