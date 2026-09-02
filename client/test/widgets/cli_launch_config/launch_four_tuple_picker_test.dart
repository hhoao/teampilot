import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/widgets/cli_launch_config/launch_four_tuple_picker.dart';
import 'package:teampilot/widgets/compose/compose_model_preset_chip.dart';

class _MockAppProviderCubit extends Mock implements AppProviderCubit {}

void main() {
  test('preset selection snapshots its launch four-tuple', () {
    final tuple = tupleFromCascadeSelection(
      value: 'preset-1',
      presets: const [
        CliPreset(
          id: 'preset-1',
          name: 'Work',
          cli: CliTool.claude,
          provider: 'anthropic',
          model: 'claude-sonnet',
          effort: 'high',
          createdAt: 1,
          updatedAt: 2,
        ),
      ],
    );

    expect(tuple?.cli, CliTool.claude);
    expect(tuple?.providerId, 'anthropic');
    expect(tuple?.modelId, 'claude-sonnet');
    expect(tuple?.effort, 'high');
  });

  test('cascade model selection returns a launch four-tuple', () {
    final tuple = tupleFromCascadeSelection(
      value: const CascadeModelPick(
        cli: CliTool.codex,
        providerId: 'openai',
        modelId: 'gpt-5',
      ),
      presets: const [],
    );

    expect(tuple?.cli, CliTool.codex);
    expect(tuple?.providerId, 'openai');
    expect(tuple?.modelId, 'gpt-5');
    expect(tuple?.effort, isEmpty);
  });

  testWidgets('builds with save hidden and manage shown by default', (
    tester,
  ) async {
    final providerCubit = _MockAppProviderCubit();
    when(() => providerCubit.state).thenReturn(const AppProviderState());
    when(
      () => providerCubit.stream,
    ).thenAnswer((_) => const Stream<AppProviderState>.empty());
    final colorScheme = ColorScheme.fromSeed(seedColor: Colors.blue);

    await tester.pumpWidget(
      BlocProvider<AppProviderCubit>.value(
        value: providerCubit,
        child: CliToolRegistryScope(
          registry: CliToolRegistry.builtIn(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: TpTheme(
              data: TpThemeData.fromColorScheme(colorScheme, scale: 1),
              child: Scaffold(
                body: LaunchFourTuplePicker(
                  value: null,
                  cliItems: const [CliTool.claude],
                  presets: const [],
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Use preset'), findsOneWidget);
    await tester.tap(find.text('Use preset'));
    await tester.pumpAndSettle();
    expect(find.text('Add Preset'), findsOneWidget);
    expect(find.text('Save current as preset…'), findsNothing);
  });
}
