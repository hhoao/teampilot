import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/managed_provider_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/pages/managed_providers/managed_provider_editor_page.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_usage_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/provider_usage/managed_provider_secret_store.dart';

import '../../support/in_memory_filesystem.dart';

class _FakeSecureKeyValueStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  late InMemoryFilesystem fs;
  late AppProviderCubit appProviderCubit;
  late ManagedProviderCubit managedProviderCubit;
  late ManagedProviderSecretStore secretStore;

  setUp(() {
    fs = InMemoryFilesystem();
    final usageRepository = ManagedProviderUsageRepository(
      fs: fs,
      cachePath: '/tp/usage-cache.json',
    );
    final managedRepository = ManagedProviderRepository(
      fs: fs,
      configPath: '/tp/managed-providers.json',
      onProvidersDeleted: usageRepository.deleteMany,
    );
    appProviderCubit = AppProviderCubit(
      repository: AppProviderRepository(fs: fs, basePath: '/tp'),
      basePath: '/tp',
    );
    managedProviderCubit = ManagedProviderCubit(
      repository: managedRepository,
      appProviderCubit: appProviderCubit,
    );
    secretStore = ManagedProviderSecretStore(_FakeSecureKeyValueStore());
  });

  tearDown(() async {
    await managedProviderCubit.close();
    await appProviderCubit.close();
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TpTheme(
          data: TpThemeData.fromColorScheme(
            ColorScheme.fromSeed(seedColor: Colors.indigo),
            scale: 1,
          ),
          child: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<ManagedProviderSecretStore>.value(
                value: secretStore,
              ),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: appProviderCubit),
                BlocProvider.value(value: managedProviderCubit),
              ],
              child: const Scaffold(
                body: ManagedProviderEditorPage(onBack: _noop),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('selecting a provider link hides the secret and persists source',
      (tester) async {
    await appProviderCubit.upsertProvider(
      const AppProviderConfig(
        id: 'deepseek',
        cli: CliTool.claude,
        name: 'DeepSeek',
        category: AppProviderCategory.thirdParty,
        apiKey: 'sk-live',
      ),
    );
    await pumpEditor(tester);

    // New entries default to the custom HTTP template, whose schema exposes
    // an editable credential source. Scroll to the (collapsed) credentials
    // section and expand it — collapsed sections stay mounted but offstage.
    await tester.scrollUntilVisible(
      find.byKey(const Key('managed-provider-section-credentials')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Credential details'));
    await tester.pumpAndSettle();

    // Open the mode picker and choose the provider row.
    await tester.tap(find.byKey(const Key('managed-provider-credential-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek (claude)').last);
    await tester.pumpAndSettle();

    // The secret input stays hidden and the read-only chip names the provider.
    expect(
      find.byKey(const Key('managed-provider-credential-secret')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('managed-provider-credential-link-chip')),
      findsOneWidget,
    );

    // Save and assert the persisted entry uses the provider credential source.
    await tester.enterText(
      find.byKey(const Key('managed-provider-name')),
      'DeepSeek balance',
    );
    await tester.enterText(
      find.byKey(const Key('managed-provider-endpoint')),
      'https://api.deepseek.com/user/balance',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('managed-provider-save')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('managed-provider-save')));
    // The save chain crosses real event-loop turns (storage lock + fs
    // writes) that fake-clock pumps do not wait for; give the loop real
    // time, then settle frames.
    await tester.runAsync(() async {
      for (var i = 0; i < 50; i++) {
        if (managedProviderCubit.state.providers.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(managedProviderCubit.state.providers, hasLength(1));
    final saved = managedProviderCubit.state.providers.single;
    expect(saved.name, 'DeepSeek balance');
    expect(saved.endpointConfig.credentialSource, 'provider:claude:deepseek');
    expect(saved.credentialRef, isNull);

    // Dispose the tree and let the success toast's timers expire.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}

void _noop() {}
