@Tags(['integration', 'linux-pty'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mock_model_gateway/scenarios/catalog_mcp_simple_claude.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/workspace_project_config_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../support/post_frame_test_harness.dart';
import '../support/rust_lib_test_init.dart';
import 'support/cli_message_matrix_harness.dart';
import 'support/integration_prerequisites.dart';
import 'support/integration_test_setup.dart';

void main() {
  setUpAll(initRustLibForTests);
  setUp(setUpIntegrationAppStorage);
  tearDown(tearDownIntegrationAppStorage);

  test(
    'claude simple: catalog MCP search_skills + create_skill writes library',
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
        await Future<void>.delayed(const Duration(seconds: 3));
      });

      try {
        await harness.startGateway(
          scenarios: catalogMcpSimpleClaudeScenarios(),
        );
        await harness.writeMockProviders();
        harness.createCubit(postFrame: postFrame);
        harness.attachCatalogRuntime();
        await harness.openSession();
        await harness.bootComposeSeatToPrompt();
        await harness.loadHistory();

        const prompt = 'search then create the l2 catalog skill';
        final result = await harness.submitCompose(prompt);
        expect(
          result.ok,
          isTrue,
          reason: 'submitCompose failed\n${harness.diagnosticsBundle()}',
        );

        await harness.waitForGatewayTurns(
          apiKey: simpleScriptApiKey,
          minTurns: 3,
        );
        await harness.waitForPtyMarkers([markCatalogOk]);

        final labels = harness.gateway!.requestLog
            .where((e) => e.apiKey == simpleScriptApiKey)
            .map((e) => e.turnLabel)
            .toList();
        expect(
          labels,
          containsAll([
            'tool:catalog.search_skills id=tu_search',
            'tool:catalog.create_skill id=tu_create',
          ]),
          reason: harness.diagnosticsBundle(),
        );

        final skillMd = File(
          p.join(
            AppStorage.paths.basePath,
            'skills',
            'installed',
            catalogL2SkillDirectory,
            'SKILL.md',
          ),
        );
        expect(
          skillMd.existsSync(),
          isTrue,
          reason:
              'create_skill must write the global library, not CONFIG_DIR\n'
              '${harness.diagnosticsBundle()}',
        );
        final body = skillMd.readAsStringSync();
        expect(body, contains(catalogL2SkillName));
        expect(body, contains(catalogL2SkillBody));

        final workspaceId = harness.workspace?.workspaceId;
        expect(workspaceId, isNotNull);
        final bound = await WorkspaceProjectConfigRepository().load(
          workspaceId!,
        );
        expect(
          bound.bundle.skillIds,
          contains('local:$catalogL2SkillDirectory'),
        );
      } catch (e, st) {
        // ignore: avoid_print
        print(harness.diagnosticsBundle());
        Error.throwWithStackTrace(e, st);
      }
    },
  );
}
