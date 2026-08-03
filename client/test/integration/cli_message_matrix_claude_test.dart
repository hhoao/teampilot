@Tags(['integration', 'linux-pty'])
@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mock_model_gateway/scenarios/mixed_collab_3plus.dart';
import 'package:mock_model_gateway/scenarios/native_collab_replica_2plus.dart';
import 'package:mock_model_gateway/scenarios/simple_3turn.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/team/claude_native_inbox_doorbell.dart';

import '../support/post_frame_test_harness.dart';
import 'support/bus_mail_assertions.dart';
import 'support/cli_message_matrix_harness.dart';
import 'support/integration_prerequisites.dart';
import 'support/integration_test_setup.dart';
import 'support/native_roster_assertions.dart';

void main() {
  setUp(setUpIntegrationAppStorage);
  tearDown(tearDownIntegrationAppStorage);

  test(
    'claude simple: History compose → user bubble → ≥3 assistant bubbles',
    () async {
      IntegrationPrerequisites.skipUnlessNativePty();
      final claudePath = IntegrationPrerequisites.requireClaudePath();
      if (claudePath == null) return;

      final harness = CliMessageMatrixHarness.forCli(
        CliTool.claude,
        mode: CliMatrixMode.simple,
        cliPath: claudePath,
      );
      final postFrame = PostFrameTestHarness();
      addTearDown(() async {
        await harness.dispose();
        await postFrame.flush();
        await drainPendingAsyncWork();
        // Let Claude PTY children release config dir handles before tearDown.
        await Future<void>.delayed(const Duration(seconds: 3));
      });

      try {
        await harness.startGateway();
        await harness.writeMockProviders();
        harness.createCubit(postFrame: postFrame);
        await harness.openSession();
        await harness.bootComposeSeatToPrompt();
        await harness.loadHistory();

        // simple_3turn is three TextTurns — one History compose per turn.
        // Settle back to the composer between submits so Claude does not queue.
        const prompts = [
          'matrix turn one please reply',
          'matrix turn two please reply',
          'matrix turn three please reply',
        ];
        final markers = const [markA1, markA2, markA3];
        for (var i = 0; i < prompts.length; i++) {
          final before = harness.gateway!.requestCountFor(simpleScriptApiKey);
          final result = await harness.submitCompose(prompts[i]);
          expect(
            result.ok,
            isTrue,
            reason: 'submitCompose failed at turn ${i + 1}\n'
                '${harness.diagnosticsBundle()}',
          );
          await harness.waitForGatewayTurns(
            apiKey: simpleScriptApiKey,
            minTurns: before + 1,
          );
          await harness.waitForPtyMarkers([markers[i]]);
          if (i < prompts.length - 1) {
            await harness.bootComposeSeatToPrompt();
          }
        }

        expect(
          harness.gateway!.requestCountFor(simpleScriptApiKey),
          greaterThanOrEqualTo(3),
          reason: harness.diagnosticsBundle(),
        );
        // Each marker was asserted when produced; alt-screen scroll drops older
        // rows from the probe window, so do not require all three at once.
        await harness.waitForBubbles(userText: prompts.first);
      } catch (e, st) {
        // ignore: avoid_print
        print(harness.diagnosticsBundle());
        Error.throwWithStackTrace(e, st);
      }
    },
  );

  test(
    'claude mixed: History compose → collab ≥3 assistant bubbles + bus',
    () async {
      IntegrationPrerequisites.skipUnlessNativePty();
      final claudePath = IntegrationPrerequisites.requireClaudePath();
      if (claudePath == null) return;

      final harness = CliMessageMatrixHarness.forCli(
        CliTool.claude,
        mode: CliMatrixMode.mixed,
        recipe: CliMatrixRecipe.mixedCollab3Plus,
        cliPath: claudePath,
      );
      final postFrame = PostFrameTestHarness();
      addTearDown(() async {
        await harness.dispose();
        await postFrame.flush();
        await drainPendingAsyncWork();
        await Future<void>.delayed(const Duration(seconds: 3));
      });

      try {
        await harness.startGateway();
        await harness.writeMockProviders();
        harness.createCubit(postFrame: postFrame);
        await harness.openSession();
        await harness.bootAllMembersToPrompt();
        await harness.loadHistory();

        // Park worker first (recipe order); idle-announce may doorbell the
        // lead — compose runs after bootComposeSeatToPrompt.
        const prompt = 'matrix mixed collab please coordinate';
        final leadScenarioTurns =
            mixedCollab3PlusScenarios()[leadScriptApiKey]!.turns.length;
        final result = await harness.parkWorkerAndComposeOnLead(prompt);
        expect(
          result.ok,
          isTrue,
          reason: 'submitCompose failed on lead\n'
              '${harness.diagnosticsBundle()}',
        );

        await harness.waitForGatewayTurns(
          apiKey: leadScriptApiKey,
          minTurns: leadScenarioTurns,
          byScenarioIndex: true,
        );
        await harness.waitForGatewayTurns(
          apiKey: workerScriptApiKey,
          minTurns:
              mixedCollab3PlusScenarios()[workerScriptApiKey]!.turns.length,
          byScenarioIndex: true,
        );
        await harness.waitForBusPingPong();
        expect(
          harness.gateway!.requestCountFor(workerScriptApiKey),
          greaterThanOrEqualTo(2),
          reason: harness.diagnosticsBundle(),
        );
        final gatewayDump = harness.gateway!.dumpDiagnostics();
        for (final marker in harness.profile.collabLeadMarkers) {
          expect(
            gatewayDump,
            contains(marker),
            reason: harness.diagnosticsBundle(),
          );
        }

        // Collab turns scroll the alt-screen; require the final lead marker
        // (earlier MARK_LEAD_* may have left the probe window).
        await harness.waitForPtyMarkers([markLeadDone]);

        // Lead parks on wait_for_message after MARK_LEAD_DONE (forceWait). Do
        // not require an idle composer — History syncs from session JSONL.
        await harness.waitForBubbles(userText: prompt);

        // Extra bus-mail sanity (same predicates as waitForBusPingPong).
        final s = harness.session!;
        final root = AppStorage.paths.basePath;
        final workerMail = await readBusMailLines(
          teampilotRoot: root,
          workspaceId: s.workspaceId,
          sessionId: s.sessionId,
          memberId: kMatrixWorkerTypeId,
        );
        expect(
          workerMail.any(
            (row) =>
                row['from'] == kMatrixLeadMemberId && row['content'] == 'ping',
          ),
          isTrue,
          reason: harness.diagnosticsBundle(),
        );
        final leadMail = await readBusMailLines(
          teampilotRoot: root,
          workspaceId: s.workspaceId,
          sessionId: s.sessionId,
          memberId: kMatrixLeadMemberId,
        );
        expect(
          leadMail.any(
            (row) =>
                row['from'] == kMatrixWorkerTypeId &&
                row['content'] == 'pong',
          ),
          isTrue,
          reason: harness.diagnosticsBundle(),
        );
        expect(
          harness.cubit!.hasTeamBusResources(s.sessionId),
          isTrue,
          reason: harness.diagnosticsBundle(),
        );
      } catch (e, st) {
        // ignore: avoid_print
        print(harness.diagnosticsBundle());
        Error.throwWithStackTrace(e, st);
      }
    },
  );

  test(
    'claude native: History compose → collab ≥3 assistant bubbles',
    () async {
      IntegrationPrerequisites.skipUnlessNativePty();
      final claudePath = IntegrationPrerequisites.requireClaudePath();
      if (claudePath == null) return;

      final harness = CliMessageMatrixHarness.forCli(
        CliTool.claude,
        mode: CliMatrixMode.native,
        shape: RosterShape.singleton,
        recipe: CliMatrixRecipe.nativeCollab3Plus,
        cliPath: claudePath,
      );
      final postFrame = PostFrameTestHarness();
      addTearDown(() async {
        await harness.dispose();
        await postFrame.flush();
        await drainPendingAsyncWork();
        await Future<void>.delayed(const Duration(seconds: 3));
      });

      try {
        await harness.startGateway();
        await harness.writeMockProviders();
        harness.createCubit(postFrame: postFrame);
        await harness.openSession();
        await harness.bootAllMembersToPrompt();
        await harness.loadHistory();

        // native_collab_3plus interleaves tools with TextTurns. A TextTurn is
        // end_turn (no mixed Stop-hook chain), so each History compose advances
        // one tool→text segment: TeamCreate/TaskCreate→MARK_LEAD_1, then
        // TaskList→MARK_LEAD_2, then TeamDelete→MARK_LEAD_DONE.
        const prompts = [
          'matrix native turn one please coordinate',
          'matrix native turn two please continue',
          'matrix native turn three please wrap up',
        ];
        final markers = const [markLead1, markLead2, markLeadDone];
        for (var i = 0; i < prompts.length; i++) {
          final before = harness.gateway!.requestCountFor(leadScriptApiKey);
          final result = await harness.submitCompose(prompts[i]);
          expect(
            result.ok,
            isTrue,
            reason: 'submitCompose failed at turn ${i + 1}\n'
                '${harness.diagnosticsBundle()}',
          );
          await harness.waitForGatewayTurns(
            apiKey: leadScriptApiKey,
            minTurns: before + 1,
          );
          await harness.waitForPtyMarkers([markers[i]]);
          if (i < prompts.length - 1) {
            await harness.bootComposeSeatToPrompt();
          }
        }

        expect(
          harness.gateway!.requestCountFor(leadScriptApiKey),
          greaterThanOrEqualTo(3),
          reason: harness.diagnosticsBundle(),
        );
        final gatewayDump = harness.gateway!.dumpDiagnostics();
        for (final marker in harness.profile.collabLeadMarkers) {
          expect(
            gatewayDump,
            contains(marker),
            reason: harness.diagnosticsBundle(),
          );
        }

        await harness.bootComposeSeatToPrompt();
        await harness.waitForBubbles(userText: prompts.first);
      } catch (e, st) {
        // ignore: avoid_print
        print(harness.diagnosticsBundle());
        Error.throwWithStackTrace(e, st);
      }
    },
  );

  test(
    'claude native replicated: pods inbox + worker-0 + 2 lead composes',
    () async {
      IntegrationPrerequisites.skipUnlessNativePty();
      final claudePath = IntegrationPrerequisites.requireClaudePath();
      if (claudePath == null) return;

      final harness = CliMessageMatrixHarness.forCli(
        CliTool.claude,
        mode: CliMatrixMode.native,
        shape: RosterShape.replicated,
        recipe: CliMatrixRecipe.nativeCollabReplica2Plus,
        cliPath: claudePath,
      );
      final postFrame = PostFrameTestHarness();
      addTearDown(() async {
        ClaudeNativeInboxDoorbell.doorbellDisabledForTests = false;
        await harness.dispose();
        await postFrame.flush();
        await drainPendingAsyncWork();
        await Future<void>.delayed(const Duration(seconds: 3));
      });

      try {
        ClaudeNativeInboxDoorbell.doorbellDisabledForTests = true;
        await harness.startGateway();
        await harness.writeMockProviders();
        harness.createCubit(
          postFrame: postFrame,
          autoLaunchAllMembersOnConnect: false,
        );
        await harness.openSession();
        await harness.bootMemberToPrompt(kMatrixLeadMemberId);

        final worker0 = matrixPrimaryWorkerPodId(harness.shape);
        // Boot idle workers before lead compose so round-1 SendMessage can land
        // in the pod inbox while pods are materialized, then doorbell reengage can
        // wake developer-0 at prompt (Acceptance #3 + production doorbell).
        await harness.connectMember('developer-1');
        await harness.bootMemberToPrompt('developer-1');
        await harness.connectMember(worker0);
        await harness.bootMemberToPrompt(worker0);

        await harness.loadHistory();

        final cliTeam = harness.session!.cliTeamName.trim().isNotEmpty
            ? harness.session!.cliTeamName
            : harness.session!.sessionId;
        final claudeDir = RuntimeLayout(teampilotRoot: AppStorage.appDataRoot)
            .sessionRuntimeToolDir(
              harness.session!.workspaceId,
              harness.session!.sessionId,
              'claude',
            );

        final leadBefore1 = harness.gateway!.requestCountFor(leadScriptApiKey);
        final r1 = await harness.submitCompose(
          'matrix replica turn one coordinate',
        );
        expect(r1.ok, isTrue, reason: harness.diagnosticsBundle());
        await harness.waitForGatewayTurns(
          apiKey: leadScriptApiKey,
          minTurns: leadBefore1 + 2,
        );
        await waitForClaudeInboxUnread(
          claudeDir: claudeDir,
          cliTeamName: cliTeam,
          memberId: 'developer-0',
        );
        await harness.waitForPtyMarkers(
          [markReplicaLead1],
          memberId: kMatrixLeadMemberId,
        );

        expectClaudeRosterPods(
          claudeDir: claudeDir,
          cliTeamName: cliTeam,
          expectedNames: const ['team-lead', 'developer-0', 'developer-1'],
          expectedAgentTypes: const {
            'team-lead': 'team-lead',
            'developer-0': 'developer',
            'developer-1': 'developer',
          },
        );
        expectClaudeInboxExists(
          claudeDir: claudeDir,
          cliTeamName: cliTeam,
          memberId: 'developer-0',
        );
        expectClaudeInboxAbsent(
          claudeDir: claudeDir,
          cliTeamName: cliTeam,
          memberId: 'developer',
        );

        final sessionPods = sessionRosterMembers(
          harness.session!,
          harness.team!,
        ).map((m) => m.id).toList();
        expect(
          sessionPods,
          containsAll(['team-lead', 'developer-0', 'developer-1']),
          reason: harness.diagnosticsBundle(),
        );

        // Acceptance #3 vs Claude live-agent: connected pods may receive
        // SendMessage in-process. Workers boot idle above (doorbell disabled) so
        // compose still writes unread mail to developer-0.json, then production
        // doorbell reengage wakes developer-0 at prompt.
        ClaudeNativeInboxDoorbell.doorbellDisabledForTests = false;

        final workerGatewayBaseline =
            harness.gateway!.requestCountFor(workerScriptApiKey);

        expect(
          harness.cubit!.activeTab!.memberShells.keys,
          containsAll([worker0, 'developer-1']),
          reason: harness.diagnosticsBundle(),
        );
        expect(
          readClaudeInboxUnreadCount(
            claudeDir: claudeDir,
            cliTeamName: cliTeam,
            memberId: 'developer-1',
          ),
          0,
          reason:
              'developer-1 should stay idle with no unread after round-1 dispatch '
              'to developer-0 only',
        );

        // Production path: idle-watch → ClaudeNativeInboxDoorbell → PTY deliver.
        await harness.waitForNativeInboxDoorbellConsume(
          workerMemberId: worker0,
          workerApiKey: workerScriptApiKey,
          markers: [markReplicaW01],
          gatewayBaseline: workerGatewayBaseline,
        );

        harness.gateway!.seekScenario(leadScriptApiKey, 3);
        await harness.bootComposeSeatToPrompt();
        final r2 = await harness.submitCompose(
          'matrix replica turn two continue',
        );
        expect(r2.ok, isTrue, reason: harness.diagnosticsBundle());
        await harness.waitForGatewayTurns(
          apiKey: leadScriptApiKey,
          minTurns: 5,
          byScenarioIndex: true,
        );
        await harness.waitForPtyMarkers(
          [markReplicaLead2],
          memberId: kMatrixLeadMemberId,
        );
      } catch (e, st) {
        ClaudeNativeInboxDoorbell.doorbellDisabledForTests = false;
        // ignore: avoid_print
        print(harness.diagnosticsBundle());
        Error.throwWithStackTrace(e, st);
      }
    },
  );
}
