import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/widgets/app_provider/provider_models_editor.dart';

void main() {
  test(
    'parse reads the background tier role and toJson omits standard role',
    () {
      final entries = ProviderModelsEditor.parse({
        'main': {'name': 'Main', 'model': 'main', 'enabled': true},
        'cheap': {
          'name': 'Cheap',
          'model': 'cheap',
          'enabled': true,
          'role': 'background',
        },
      });

      final main = entries.firstWhere((e) => e.id == 'main');
      final cheap = entries.firstWhere((e) => e.id == 'cheap');
      expect(main.tier, ProviderModelTier.standard);
      expect(cheap.tier, ProviderModelTier.background);

      // Standard role is not persisted; background is.
      expect(main.toJson().containsKey('role'), isFalse);
      expect(cheap.toJson()['role'], 'background');
    },
  );

  test('parse reads name/model/enabled and preserves extra keys', () {
    final entries = ProviderModelsEditor.parse({
      'deepseek-chat': {
        'name': 'DeepSeek Chat',
        'model': 'deepseek-chat',
        'enabled': true,
        'provider': 'DeepSeek',
      },
    });

    expect(entries, hasLength(1));
    final entry = entries.single;
    expect(entry.id, 'deepseek-chat');
    expect(entry.name, 'DeepSeek Chat');
    expect(entry.model, 'deepseek-chat');
    expect(entry.enabled, isTrue);
    expect(entry.raw['provider'], 'DeepSeek');

    // Round-trip keeps the extra key and the core fields.
    expect(entry.toJson(), {
      'provider': 'DeepSeek',
      'name': 'DeepSeek Chat',
      'model': 'deepseek-chat',
      'enabled': true,
    });
  });

  test('parse falls back to key when value is not a map', () {
    final entries = ProviderModelsEditor.parse({'gpt-5.4': 'gpt-5.4'});
    final entry = entries.single;
    expect(entry.id, 'gpt-5.4');
    expect(entry.name, 'gpt-5.4');
    expect(entry.model, 'gpt-5.4');
    expect(entry.enabled, isTrue);
  });

  test('parse returns empty for null models', () {
    expect(ProviderModelsEditor.parse(null), isEmpty);
  });

  test('parse reads contextWindow without duplicating it in raw', () {
    final entries = ProviderModelsEditor.parse({
      'glm': {
        'name': 'GLM',
        'model': 'glm',
        'enabled': true,
        'contextWindow': 200000,
        'provider': 'DeepSeek',
      },
    });

    final entry = entries.single;
    expect(entry.contextWindow, 200000);
    expect(entry.raw.containsKey('contextWindow'), isFalse);
    expect(entry.toJson(), {
      'provider': 'DeepSeek',
      'name': 'GLM',
      'model': 'glm',
      'enabled': true,
      'contextWindow': 200000,
    });
  });

  test('parse ignores invalid contextWindow and toJson omits it', () {
    final entries = ProviderModelsEditor.parse({
      'zero': {'model': 'zero', 'contextWindow': 0},
      'none': {'model': 'none'},
    });

    expect(entries.every((e) => e.contextWindow == null), isTrue);
    for (final entry in entries) {
      expect(entry.toJson().containsKey('contextWindow'), isFalse);
    }
  });

  testWidgets('model dialog shows the context window for any CLI', (
    tester,
  ) async {
    for (final cli in [CliTool.qoder, CliTool.codebuddy, CliTool.claude]) {
      await tester.pumpWidget(_wrapEditor(cli));
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('Context window (tokens)'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
  });
}

Widget _wrapEditor(CliTool cli) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizationsCompatDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: appLocalizationsSupportedLocales,
    home: Scaffold(
      body: CliToolRegistryScope(
        registry: CliToolRegistry.builtIn(),
        child: ProviderModelsEditor(
          cli: cli,
          draftProvider: () => AppProviderConfig(id: 'p', cli: cli, name: 'P'),
          models: const {},
          defaultModel: '',
          onChanged: (_, _) {},
        ),
      ),
    ),
  );
}
