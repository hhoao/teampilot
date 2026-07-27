@Tags(['integration', 'linux-pty'])
@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mock_model_gateway/scenarios/mixed_collab_3plus.dart';
import 'package:mock_model_gateway/scenarios/simple_3turn.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../support/post_frame_test_harness.dart';
import 'support/bus_mail_assertions.dart';
import 'support/cli_message_matrix_harness.dart';
import 'support/integration_prerequisites.dart';
import 'support/integration_test_setup.dart';

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
        );
        await harness.waitForGatewayTurns(
          apiKey: workerScriptApiKey,
          minTurns:
              mixedCollab3PlusScenarios()[workerScriptApiKey]!.turns.length,
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
          memberId: kMatrixWorkerMemberId,
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
                row['from'] == kMatrixWorkerMemberId &&
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
}
