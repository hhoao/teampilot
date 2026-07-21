@Tags(['integration', 'linux-pty'])
@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mock_model_gateway/scenarios/simple_3turn.dart';
import 'package:teampilot/models/team_config.dart';

import '../support/post_frame_test_harness.dart';
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
}
