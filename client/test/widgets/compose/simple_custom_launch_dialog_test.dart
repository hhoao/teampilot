import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/widgets/compose/simple_custom_launch_dialog.dart';

/// Test-only cubit that seeds provider state without disk I/O.
class _SeededAppProviderCubit extends AppProviderCubit {
  _SeededAppProviderCubit(AppProviderState initial) {
    emit(initial);
  }
}

const _claudeProviders = AppProviderState(
  providersByCli: {
    CliTool.claude: [
      AppProviderConfig(
        id: 'claude-official',
        cli: CliTool.claude,
        name: 'Official',
        defaultModel: 'sonnet',
      ),
    ],
  },
);

Widget _host({
  required AppProviderCubit providers,
  required Widget home,
}) {
  // Scope + cubit must wrap MaterialApp so showDialog overlays inherit them.
  return CliToolRegistryScope(
    registry: CliToolRegistry.builtIn(),
    child: BlocProvider<AppProviderCubit>.value(
      value: providers,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
}

void main() {
  test('SimpleCustomLaunchResult holds four-tuple', () {
    const result = SimpleCustomLaunchResult(
      cli: CliTool.cursor,
      provider: 'cursor-account',
      model: 'gpt',
      effort: 'high',
    );
    expect(result.cli, CliTool.cursor);
    expect(result.provider, 'cursor-account');
    expect(result.model, 'gpt');
    expect(result.effort, 'high');
  });

  testWidgets('locked-cli dialog shows title and confirm returns seed', (
    tester,
  ) async {
    final providers = _SeededAppProviderCubit(_claudeProviders);
    addTearDown(providers.close);

    SimpleCustomLaunchResult? result;
    await tester.pumpWidget(
      _host(
        providers: providers,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showSimpleCustomLaunchDialog(
                  context,
                  initialCli: CliTool.claude,
                  initialProvider: 'claude-official',
                  initialModel: 'sonnet',
                  initialEffort: '',
                  lockCli: true,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Custom launch'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.cli, CliTool.claude);
    expect(result!.provider, 'claude-official');
    expect(result!.model, 'sonnet');
    expect(result!.effort, '');
  });

  testWidgets(
    'landing dialog with null initialCli allows confirm returning Claude',
    (tester) async {
      final providers = _SeededAppProviderCubit(_claudeProviders);
      addTearDown(providers.close);

      SimpleCustomLaunchResult? result;
      await tester.pumpWidget(
        _host(
          providers: providers,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showSimpleCustomLaunchDialog(
                    context,
                    initialCli: null,
                    initialProvider: '',
                    initialModel: '',
                    initialEffort: '',
                    lockCli: false,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Custom launch'), findsOneWidget);
      final confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirm'),
      );
      expect(confirm.onPressed, isNotNull);

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.cli, CliTool.claude);
      expect(result!.provider, '');
      expect(result!.model, '');
      expect(result!.effort, '');
    },
  );
}
