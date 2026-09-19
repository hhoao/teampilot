import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/ai_feature_settings_cubit.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/ai_feature_setting.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/services/chat/team_generation/team_generation_settings_store.dart';

import '../../../support/in_memory_filesystem.dart';
import '../../../support/post_frame_test_harness.dart';

const _providerId = 'test-provider';
const _modelId = 'test-model';

class _SeededAppProviderCubit extends AppProviderCubit {
  _SeededAppProviderCubit() : super(storage: buildTestHomeStorage()) {
    emit(
      const AppProviderState(
        providersByCli: {
          CliTool.claude: [
            AppProviderConfig(
              id: _providerId,
              cli: CliTool.claude,
              name: 'Test provider',
            ),
          ],
        },
      ),
    );
  }
}

final _generatorSetting = AiFeatureSetting(
  cli: CliTool.claude,
  providerId: _providerId,
  model: _modelId,
);

final _modelPool = [
  GenerateModelPoolEntry(
    id: 'pool-entry',
    cli: CliTool.claude,
    provider: _providerId,
    model: _modelId,
  ),
];

Widget buildGenerateSettingsTestHost() {
  final aiSettingsCubit = AiFeatureSettingsCubit(
    repository: InMemoryAppSettingsRepository(),
  );
  final appProviderCubit = _SeededAppProviderCubit();
  final presetsCubit = CliPresetsCubit(
    repository: CliPresetsRepository(
      fs: InMemoryFilesystem(),
      presetsPath: '/cli-presets.json',
    ),
  );
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);

  return MultiRepositoryProvider(
    providers: [RepositoryProvider<HomeStorage>.value(value: testHomeStorage)],
    child: MultiBlocProvider(
      providers: [
        BlocProvider<AiFeatureSettingsCubit>(create: (_) => aiSettingsCubit),
        BlocProvider<AppProviderCubit>(create: (_) => appProviderCubit),
        BlocProvider<CliPresetsCubit>(create: (_) => presetsCubit),
      ],
      child: CliToolRegistryScope(
        registry: CliToolRegistry.builtIn(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(colorScheme: scheme, useMaterial3: true),
          home: TpTheme(
            data: TpThemeData.fromColorScheme(scheme, scale: 1),
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () {
                    showWorkspaceLandingGenerateSettingsDialog(
                      context,
                      presets: const <CliPreset>[],
                      generatorSetting: _generatorSetting,
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _waitForGenerateSettingsLoad(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late TeamGenerationSettingsStore testSettingsStore;

  setUp(() async {
    setUpTestAppStorage();
    installTestHomeStorage(
      filesystem: InMemoryFilesystem(),
      paths: AppPaths('/test-home'),
    );
    testSettingsStore = TeamGenerationSettingsStore(storage: testHomeStorage);
    await testSettingsStore.save(TeamGenerationSettings(modelPool: _modelPool));
  });
  tearDown(tearDownTestAppStorage);

  test('native team launchable excludes non-native clis like codex', () {
    final registry = CliToolRegistry.builtIn();
    final nativeIds = {
      for (final definition in registry.nativeTeamLaunchable) definition.id,
    };

    expect(nativeIds, contains(CliTool.claude));
    expect(nativeIds, isNot(contains(CliTool.codex)));
    expect(nativeIds, isNot(contains(CliTool.cursor)));
  });

  test(
    'generator may use any launchable cli even when native team is locked',
    () {
      final registry = CliToolRegistry.builtIn();
      final launchable = {
        for (final definition in registry.launchable) definition.id,
      };
      final native = {
        for (final definition in registry.nativeTeamLaunchable) definition.id,
      };

      // Product rule: pool is native-filtered; generator is not.
      expect(launchable.difference(native), isNotEmpty);
      expect(launchable, contains(CliTool.codex));
    },
  );

  testWidgets('loads three and saves a larger minimum', (tester) async {
    await tester.pumpWidget(buildGenerateSettingsTestHost());
    await tester.tap(find.text('Open'));
    await _waitForGenerateSettingsLoad(tester);

    final minimumField = find.byKey(
      const ValueKey('team-generate-minimum-members'),
    );
    expect(minimumField, findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Minimum team members'), findsOneWidget);
    expect(
      find.text(
        'The generated team will include at least this many distinct roles.',
      ),
      findsOneWidget,
    );

    await tester.enterText(minimumField, '8');
    await tester.tap(find.text('Save'));
    await _waitForGenerateSettingsLoad(tester);

    expect((await testSettingsStore.load()).minimumMemberCount, 8);
  });

  testWidgets('blocks values below three', (tester) async {
    await tester.pumpWidget(buildGenerateSettingsTestHost());
    await tester.tap(find.text('Open'));
    await _waitForGenerateSettingsLoad(tester);

    await tester.enterText(
      find.byKey(const ValueKey('team-generate-minimum-members')),
      '2',
    );
    await tester.pump();

    expect(find.text('Minimum must be at least 3.'), findsOneWidget);
  });

  testWidgets('blocks empty and non-integer values', (tester) async {
    await tester.pumpWidget(buildGenerateSettingsTestHost());
    await tester.tap(find.text('Open'));
    await _waitForGenerateSettingsLoad(tester);

    final minimumField = find.byKey(
      const ValueKey('team-generate-minimum-members'),
    );
    await tester.enterText(minimumField, 'not-a-number');
    await tester.pump();

    expect(find.text('Minimum must be at least 3.'), findsOneWidget);
    final saveButton = find.ancestor(
      of: find.text('Save'),
      matching: find.byType(TextButton),
    );
    expect(tester.widget<TextButton>(saveButton).onPressed, isNull);

    await tester.enterText(minimumField, '');
    await tester.pump();

    expect(find.text('Minimum must be at least 3.'), findsOneWidget);
  });
}
