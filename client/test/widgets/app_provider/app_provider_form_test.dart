import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/widgets/app_provider/app_provider_form_sheet.dart';
import 'package:teampilot/widgets/dropdown/app_dropdown_field.dart';

void main() {
  testWidgets('claude provider form shows advanced options', (tester) async {
    await tester.pumpWidget(
      _wrapForm(
        AppProviderFormPage(
          cli: CliTool.claude,
          onCancel: () {},
          onSaved: (_) {},
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Advanced options'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Advanced options'), findsOneWidget);
    expect(find.text('Authentication field'), findsOneWidget);
    // The dead 'API format' field was removed too.
    expect(find.text('API format'), findsNothing);
    // Legacy per-tier model-mapping fields were removed; tiers now come from
    // the model list (⭐ main / ⚡ background).
    expect(find.text('Haiku default model'), findsNothing);
    expect(find.text('Sonnet default model'), findsNothing);
    expect(find.text('Opus default model'), findsNothing);
  });

  testWidgets('switching cli resets preset dropdown without crashing', (
    tester,
  ) async {
    var cli = CliTool.codex;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CliToolRegistryScope(
          registry: CliToolRegistry.builtIn(),
          child: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: SizedBox(
                width: 900,
                height: 1000,
                child: AppProviderFormPage(
                  key: ValueKey(cli),
                  cli: cli,
                  onCliChanged: (next) => setState(() => cli = next),
                  onCancel: () {},
                  onSaved: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AppDropdownField<CliTool>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude Code').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Advanced options'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Advanced options'), findsOneWidget);
  });

  testWidgets('claude provider form drops legacy per-tier mapping fields', (
    tester,
  ) async {
    AppProviderConfig? saved;
    await tester.pumpWidget(
      _wrapForm(
        AppProviderFormPage(
          cli: CliTool.claude,
          existing: const AppProviderConfig(
            id: 'test-provider',
            cli: CliTool.claude,
            name: 'Test Provider',
            baseUrl: 'https://api.test',
            defaultModel: 'main-model',
          ),
          onCancel: () {},
          onSaved: (provider) => saved = provider,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Advanced options'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    // The raw per-tier mapping fields are gone; tiers come from the model list.
    expect(find.text('Haiku default model'), findsNothing);
    expect(find.text('Sonnet default model'), findsNothing);
    expect(find.text('Opus default model'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    // Endpoint/model stay on the canonical top-level fields ...
    expect(saved!.baseUrl, 'https://api.test');
    expect(saved!.defaultModel, 'main-model');
    expect(saved!.apiKeyField, 'ANTHROPIC_AUTH_TOKEN');
    // ... and the record is slim: no frozen derived env, apiFormat, or the
    // duplicate api_key_field. The launch materializer derives env from above.
    final env = (saved!.config['env'] as Map?) ?? const {};
    expect(saved!.config.containsKey('apiFormat'), isFalse);
    expect(saved!.config.containsKey('api_key_field'), isFalse);
    expect(env.containsKey('ANTHROPIC_BASE_URL'), isFalse);
    expect(env.containsKey('ANTHROPIC_MODEL'), isFalse);
    expect(env.containsKey('ANTHROPIC_DEFAULT_HAIKU_MODEL'), isFalse);
  });
}

Widget _wrapForm(Widget form) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: CliToolRegistryScope(
      registry: CliToolRegistry.builtIn(),
      child: Scaffold(
        body: SizedBox(
          width: 1000,
          height: 1400,
          child: form,
        ),
      ),
    ),
  );
}
