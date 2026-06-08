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
    expect(find.text('API format'), findsOneWidget);
    expect(find.text('Authentication field'), findsOneWidget);
    expect(find.text('Haiku default model'), findsOneWidget);
    expect(find.text('Sonnet default model'), findsOneWidget);
    expect(find.text('Opus default model'), findsOneWidget);
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
      find.text('API format'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('API format'), findsOneWidget);
  });

  testWidgets('claude provider form saves model mapping into env', (
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
    await tester.enterText(_fieldWithLabel('Haiku default model'), 'haiku');
    await tester.enterText(_fieldWithLabel('Sonnet default model'), 'sonnet');
    await tester.enterText(_fieldWithLabel('Opus default model'), 'opus');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    final env = saved!.config['env'] as Map<String, Object?>;
    expect(saved!.config['apiFormat'], 'anthropic');
    expect(saved!.config['api_key_field'], 'ANTHROPIC_AUTH_TOKEN');
    expect(env['ANTHROPIC_BASE_URL'], 'https://api.test');
    expect(env['ANTHROPIC_MODEL'], 'main-model');
    expect(env['ANTHROPIC_DEFAULT_HAIKU_MODEL'], 'haiku');
    expect(env['ANTHROPIC_DEFAULT_SONNET_MODEL'], 'sonnet');
    expect(env['ANTHROPIC_DEFAULT_OPUS_MODEL'], 'opus');
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

Finder _fieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
}
