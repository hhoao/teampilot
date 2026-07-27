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
import 'support/cli_test_profile.dart';
import 'support/integration_prerequisites.dart';
import 'support/integration_test_setup.dart';

void main() {
  setUp(setUpIntegrationAppStorage);
  tearDown(tearDownIntegrationAppStorage);

  test('codex native is N/A', () {
    expect(CliTestProfiles.forTool(CliTool.codex).supportsNativeTeam, isFalse);
  });

  test(
    'codex simple: History compose → user bubble → ≥3 assistant bubbles',
    () async {
      IntegrationPrerequisites.skipUnlessNativePty();
      final codexPath = IntegrationPrerequisites.requireCodexPath();
      if (codexPath == null) return;

      final harness = CliMessageMatrixHarness.forCli(
        CliTool.codex,
        mode: CliMatrixMode.simple,
        cliPath: codexPath,
      );
      final postFrame = PostFrameTestHarness();
      addTearDown(() async {
        await harness.dispose();
        await postFrame.flush();
        await drainPendingAsyncWork();
        // Let Codex PTY children release CODEX_HOME handles before tearDown.
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
        // Settle back to the composer between submits so Codex does not queue.
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
    'codex mixed: History compose → collab ≥3 assistant bubbles + bus',
    () async {
      IntegrationPrerequisites.skipUnlessNativePty();
      final codexPath = IntegrationPrerequisites.requireCodexPath();
      if (codexPath == null) return;

      final harness = CliMessageMatrixHarness.forCli(
        CliTool.codex,
        mode: CliMatrixMode.mixed,
        recipe: CliMatrixRecipe.mixedCollab3Plus,
        cliPath: codexPath,
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
}
