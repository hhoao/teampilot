import 'package:flutter_test/flutter_test.dart';
import 'package:mock_model_gateway/scenarios/simple_3turn.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/post_frame_test_harness.dart';
import 'cli_message_matrix_harness.dart';
import 'cli_test_profile.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('startGateway + writeMockProviders for simple claude cell', () async {
    final harness = CliMessageMatrixHarness.forCli(
      CliTool.claude,
      mode: CliMatrixMode.simple,
    );
    addTearDown(harness.dispose);

    expect(harness.recipe, CliMatrixRecipe.simple3Turn);
    await harness.startGateway();
    await harness.writeMockProviders();

    final providers = await AppProviderRepository(
      basePath: AppStorage.paths.basePath,
    ).loadProviders(CliTool.claude);
    expect(providers, hasLength(1));
    expect(providers.single.id, kMatrixSimpleProviderId);
    expect(providers.single.apiKey, simpleScriptApiKey);
    expect(providers.single.baseUrl, harness.mockBaseUrl);

    expect(harness.gateway!.requestLog, isEmpty);
    final dump = harness.diagnosticsBundle();
    expect(dump, contains('MockModelGatewayServer'));
    expect(dump, contains('mode=simple'));
  });

  test('homogeneous team builders pin row CLI on every member', () {
    for (final mode in [CliMatrixMode.native, CliMatrixMode.mixed]) {
      final harness = CliMessageMatrixHarness(
        profile: CliTestProfiles.forTool(CliTool.opencode),
        mode: mode,
      );
      if (mode == CliMatrixMode.native) {
        expect(
          () => harness.buildHomogeneousTeam(),
          throwsStateError,
          reason: 'opencode native must throw (unsupported)',
        );
        continue;
      }
      final team = harness.buildHomogeneousTeam();
      expect(team.cli, CliTool.opencode);
      expect(team.teamMode, TeamMode.mixed);
      expect(
        team.members.every((m) => (m.cli ?? team.cli) == CliTool.opencode),
        isTrue,
      );
    }
  });

  test('defaultRecipeFor maps modes', () {
    expect(
      CliMessageMatrixHarness.defaultRecipeFor(CliMatrixMode.simple),
      CliMatrixRecipe.simple3Turn,
    );
    expect(
      CliMessageMatrixHarness.defaultRecipeFor(CliMatrixMode.native),
      CliMatrixRecipe.nativeCollab3Plus,
    );
    expect(
      CliMessageMatrixHarness.defaultRecipeFor(CliMatrixMode.mixed),
      CliMatrixRecipe.mixedCollab3Plus,
    );
  });
}
