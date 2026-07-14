import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/onboarding/steps/default_preset_step.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/widgets/app_provider/cli_effort_picker_field.dart';
import 'package:teampilot/widgets/app_provider/provider_model_picker_field.dart';
import 'package:teampilot/widgets/settings/workspace_settings_widgets.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

/// Test-only cubit that seeds provider state without disk I/O.
class _SeededAppProviderCubit extends AppProviderCubit {
  _SeededAppProviderCubit(AppProviderState initial) {
    emit(initial);
  }
}

Future<void> _pumpDefaultPresetStep(
  WidgetTester tester, {
  required AppProviderState providerState,
}) async {
  final providerCubit = _SeededAppProviderCubit(providerState);
  addTearDown(providerCubit.close);

  final launchRoot = Directory.systemTemp.createTempSync('onboarding_preset_');
  addTearDown(() => launchRoot.deleteSync(recursive: true));

  final launchCubit = LaunchProfileCubit(
    repository: testLaunchProfileRepository(launchRoot),
    sessionRepository: SessionRepository(),
    executableResolver: () => 'claude',
  );
  addTearDown(launchCubit.close);

  final cliPresetsCubit = CliPresetsCubit(
    repository: CliPresetsRepository(
      fs: InMemoryFilesystem(),
      presetsPath: '/cli-presets.json',
    ),
  );
  addTearDown(cliPresetsCubit.close);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: launchCubit),
          BlocProvider.value(value: cliPresetsCubit),
          BlocProvider<AppProviderCubit>.value(value: providerCubit),
        ],
        child: CliToolRegistryScope(
          registry: CliToolRegistry.builtIn(),
          child: const Scaffold(
            body: SingleChildScrollView(
              child: OnboardingDefaultPresetStep(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets(
    'shows CLI picker when default CLI has no providers so user can switch',
    (tester) async {
      await _pumpDefaultPresetStep(
        tester,
        providerState: const AppProviderState(
          providersByCli: {
            CliTool.claude: [],
            CliTool.codex: [
              AppProviderConfig(
                id: 'codex-openai',
                cli: CliTool.codex,
                name: 'OpenAI',
                baseUrl: 'https://api.openai.com',
                defaultModel: 'gpt-5',
              ),
            ],
          },
        ),
      );

      expect(
        find.text(
          'No providers to choose from. Skip this step or add providers in Settings.',
        ),
        findsOneWidget,
      );
      // Regression: empty-provider state used to hide the CLI picker entirely,
      // trapping users who picked a CLI with no providers.
      expect(find.text('CLI backend'), findsOneWidget);
      expect(find.byType(SettingsCompactDropdown<String>), findsOneWidget);
    },
  );

  testWidgets(
    'shows model and effort when providers exist even before explicit pick',
    (tester) async {
      await _pumpDefaultPresetStep(
        tester,
        providerState: const AppProviderState(
          providersByCli: {
            CliTool.claude: [
              AppProviderConfig(
                id: 'packy',
                cli: CliTool.claude,
                name: 'Packy',
                baseUrl: 'https://api.example.com',
                defaultModel: 'claude-sonnet-4-6',
              ),
            ],
          },
        ),
      );

      expect(find.text('Default model'), findsOneWidget);
      expect(find.byType(ProviderModelPickerField), findsOneWidget);
      expect(find.text('Reasoning effort'), findsOneWidget);
      expect(find.byType(CliEffortPickerField), findsOneWidget);
    },
  );

  testWidgets(
    'shows model and effort after switching CLI that has providers',
    (tester) async {
      await _pumpDefaultPresetStep(
        tester,
        providerState: const AppProviderState(
          providersByCli: {
            CliTool.claude: [
              AppProviderConfig(
                id: 'packy',
                cli: CliTool.claude,
                name: 'Packy',
                baseUrl: 'https://api.example.com',
                defaultModel: 'claude-sonnet-4-6',
              ),
            ],
            CliTool.codex: [
              AppProviderConfig(
                id: 'codex-openai',
                cli: CliTool.codex,
                name: 'OpenAI',
                baseUrl: 'https://api.openai.com',
                defaultModel: 'gpt-5',
              ),
            ],
          },
        ),
      );

      await tester.tap(find.byType(SettingsCompactDropdown<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Codex').last);
      await tester.pumpAndSettle();

      expect(find.text('Default model'), findsOneWidget);
      expect(find.byType(ProviderModelPickerField), findsOneWidget);
      expect(find.text('Reasoning effort'), findsOneWidget);
      expect(find.byType(CliEffortPickerField), findsOneWidget);
    },
  );

  testWidgets(
    'shows model and effort when preset provider id is empty but providers exist',
    (tester) async {
      final providerCubit = _SeededAppProviderCubit(
        const AppProviderState(
          providersByCli: {
            CliTool.claude: [
              AppProviderConfig(
                id: 'packy',
                cli: CliTool.claude,
                name: 'Packy',
                baseUrl: 'https://api.example.com',
                defaultModel: 'claude-sonnet-4-6',
              ),
            ],
          },
        ),
      );
      addTearDown(providerCubit.close);

      final launchRoot = Directory.systemTemp.createTempSync(
        'onboarding_preset_',
      );
      addTearDown(() => launchRoot.deleteSync(recursive: true));

      final launchCubit = LaunchProfileCubit(
        repository: testLaunchProfileRepository(launchRoot),
        sessionRepository: SessionRepository(),
        executableResolver: () => 'claude',
      );
      addTearDown(launchCubit.close);

      final fs = InMemoryFilesystem();
      await fs.writeString(
        '/cli-presets.json',
        '[{"id":"p1","name":"Default","cli":"claude","provider":"","model":"","effort":""}]',
      );
      final cliPresetsCubit = CliPresetsCubit(
        repository: CliPresetsRepository(
          fs: fs,
          presetsPath: '/cli-presets.json',
        ),
      );
      await cliPresetsCubit.load();
      addTearDown(cliPresetsCubit.close);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: launchCubit),
              BlocProvider.value(value: cliPresetsCubit),
              BlocProvider<AppProviderCubit>.value(value: providerCubit),
            ],
            child: CliToolRegistryScope(
              registry: CliToolRegistry.builtIn(),
              child: const Scaffold(
                body: SingleChildScrollView(
                  child: OnboardingDefaultPresetStep(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Default model'), findsOneWidget);
      expect(find.byType(ProviderModelPickerField), findsOneWidget);
      expect(find.text('Reasoning effort'), findsOneWidget);
    },
  );
}
