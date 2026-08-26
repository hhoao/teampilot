import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/managed_provider_cubit.dart';
import 'package:teampilot/cubits/managed_provider_usage_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/pages/managed_providers/managed_provider_management_page.dart';
import 'package:teampilot/widgets/settings/workspace_pane_header.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_usage_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/provider_usage/managed_provider_secret_store.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_coordinator.dart'
    hide ManagedProviderUsageState;
import 'package:teampilot/services/provider_usage/managed_provider_usage_registry.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';

import '../../support/in_memory_filesystem.dart';

ManagedProvider _provider({String id = 'p1', String name = 'Example'}) =>
    ManagedProvider(
      id: id,
      name: name,
      kind: ManagedProviderKind.apiBalance,
      adapterId: 'fake',
      endpointConfig: ManagedProviderEndpointConfig(
        url: 'https://example.test/usage',
      ),
    );

ProviderUsageSnapshot _snapshot({
  ProviderUsageStatus status = ProviderUsageStatus.ready,
}) => ProviderUsageSnapshot(
  providerId: 'p1',
  status: status,
  measures: [
    ProviderUsageMeasure(
      label: 'Balance',
      kind: ProviderUsageMeasureKind.balance,
      remaining: '12.50',
      unit: 'USD',
    ),
  ],
  fetchedAt: 100,
  staleAt: 1_000,
  lastErrorCode: status == ProviderUsageStatus.error ? 'networkFailed' : null,
  lastErrorMessage: status == ProviderUsageStatus.error
      ? 'Unable to query provider usage.'
      : null,
);

class _Adapter implements ManagedProviderUsageAdapter {
  _Adapter(this.result, {this.adapterId = 'fake'});

  Future<ProviderUsageSnapshot> result;
  final String adapterId;
  Object? error;
  int calls = 0;

  @override
  String get id => adapterId;

  @override
  Future<ProviderUsageSnapshot> fetch(
    ManagedProvider provider, {
    required ProviderCredentialResolver credentials,
    required ProviderUsageHttpClient http,
    required DateTime now,
  }) async {
    calls++;
    final error = this.error;
    if (error != null) throw error;
    return result;
  }
}

class _NoCredentials implements ProviderCredentialResolver {
  @override
  Future<ProviderCredentialScope> resolve(ManagedProvider provider) async =>
      ManagedProviderCredentialScope(const {});
}

class _NoHttp implements ProviderUsageHttpClient {
  @override
  Future<ProviderUsageHttpResponse> send(ProviderUsageHttpRequest request) {
    return Future.error(StateError('HTTP should not be called by this test'));
  }
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

Finder _verticalScrollable() => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable &&
      widget.axisDirection == AxisDirection.down &&
      widget.physics is AlwaysScrollableScrollPhysics,
);

Future<void> _scrollToEditorBottom(WidgetTester tester) async {
  tester.binding.focusManager.primaryFocus?.unfocus();
  await tester.pump();
  final scrollable = tester.state<ScrollableState>(_verticalScrollable());
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pumpAndSettle();
}

Future<void> _scrollToEditorTop(WidgetTester tester) async {
  tester.binding.focusManager.primaryFocus?.unfocus();
  await tester.pump();
  final scrollable = tester.state<ScrollableState>(_verticalScrollable());
  scrollable.position.jumpTo(0);
  await tester.pumpAndSettle();
}

class _MemorySecureKeyValueStore implements SecureKeyValueStore {
  final values = <String, String>{};
  Object? writeError;

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    final error = writeError;
    if (error != null) throw error;
    values[key] = value;
  }
}

void main() {
  late InMemoryFilesystem fs;
  late ManagedProviderRepository providerRepository;
  late ManagedProviderUsageRepository usageRepository;
  late ManagedProviderCubit providerCubit;
  late ManagedProviderUsageCubit usageCubit;
  late AppProviderCubit appProviderCubit;
  late _Adapter adapter;
  late _Adapter httpJsonAdapter;
  late _RecordingNavigatorObserver navigatorObserver;
  late _MemorySecureKeyValueStore secureStore;
  late ManagedProviderUsageCoordinator coordinator;

  setUp(() async {
    fs = InMemoryFilesystem();
    usageRepository = ManagedProviderUsageRepository(
      fs: fs,
      cachePath: '/tp/usage-cache.json',
      now: () => 100,
    );
    providerRepository = ManagedProviderRepository(
      fs: fs,
      configPath: '/tp/providers.json',
      onProvidersDeleted: usageRepository.deleteMany,
    );
    adapter = _Adapter(Future.value(_snapshot()));
    httpJsonAdapter = _Adapter(
      Future.value(_snapshot()),
      adapterId: 'http-json',
    );
    navigatorObserver = _RecordingNavigatorObserver();
    secureStore = _MemorySecureKeyValueStore();
    coordinator = ManagedProviderUsageCoordinator(
      providerRepository: providerRepository,
      usageRepository: usageRepository,
      registry: ManagedProviderUsageRegistry([adapter, httpJsonAdapter]),
      credentials: _NoCredentials(),
      http: _NoHttp(),
      now: () => DateTime.fromMillisecondsSinceEpoch(100),
    );
    providerCubit = ManagedProviderCubit(repository: providerRepository);
    usageCubit = ManagedProviderUsageCubit(coordinator: coordinator);
    appProviderCubit = AppProviderCubit(
      repository: AppProviderRepository(fs: fs, basePath: '/tp'),
      basePath: '/tp',
    );
  });

  tearDown(() async {
    await providerCubit.close();
    await usageCubit.close();
    await appProviderCubit.close();
    await coordinator.close();
  });

  test('secure store propagates backend write failures', () async {
    secureStore.writeError = StateError('backend failure');
    await expectLater(
      ManagedProviderSecretStore(
        secureStore,
      ).write('managed-provider:test', {'apiKey': 'secret'}),
      throwsA(isA<ManagedProviderCredentialError>()),
    );
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: [navigatorObserver],
        home: TpTheme(
          data: TpThemeData.fromColorScheme(
            ColorScheme.fromSeed(seedColor: Colors.indigo),
            scale: 1,
          ),
          child: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: providerCubit),
              BlocProvider.value(value: usageCubit),
              BlocProvider.value(value: appProviderCubit),
              BlocProvider(create: (_) => LayoutCubit()),
              RepositoryProvider.value(
                value: ManagedProviderSecretStore(secureStore),
              ),
            ],
            child: CliToolRegistryScope(
              registry: CliToolRegistry.builtIn(),
              child: const Scaffold(
                body: ManagedProviderManagementPage(embedded: true),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> openNewEditor(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('managed-provider-add')));
    await tester.pumpAndSettle();
  }

  Future<void> applyPreset(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const Key('managed-provider-quick-preset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('renders cached usage without starting a network query', (
    tester,
  ) async {
    providerCubit.emit(
      ManagedProviderState(
        status: ManagedProviderLoadStatus.ready,
        providers: [_provider()],
      ),
    );
    usageCubit.emit(
      ManagedProviderUsageState(
        status: ManagedProviderUsageLoadStatus.ready,
        snapshots: {'p1': _snapshot()},
      ),
    );

    await pumpPage(tester);

    expect(find.text('12.50 USD'), findsOneWidget);
    expect(adapter.calls, 0);
  });

  testWidgets('list chrome matches workspace pane header and body inset', (
    tester,
  ) async {
    providerCubit.emit(
      ManagedProviderState(
        status: ManagedProviderLoadStatus.ready,
        providers: [_provider()],
      ),
    );
    usageCubit.emit(
      ManagedProviderUsageState(
        status: ManagedProviderUsageLoadStatus.ready,
      ),
    );

    await pumpPage(tester);

    expect(find.byType(WorkspacePaneHeader), findsOneWidget);
    expect(
      find.text(
        'Balances and quotas independent from CLI provider configuration.',
      ),
      findsNothing,
    );

    final headerLeft = tester.getTopLeft(find.byType(WorkspacePaneHeader)).dx;
    final listLeft = tester
        .getTopLeft(find.byKey(const Key('managed-provider-list')))
        .dx;
    final cardLeft = tester
        .getTopLeft(find.byKey(const Key('managed-provider-p1')))
        .dx;
    expect(listLeft, headerLeft);
    expect(cardLeft, headerLeft);
  });

  testWidgets('list cards hide adapter ids and keep actions on one row', (
    tester,
  ) async {
    providerCubit.emit(
      ManagedProviderState(
        status: ManagedProviderLoadStatus.ready,
        providers: [
          _provider(),
          ManagedProvider(
            id: 'codex',
            name: 'Codex',
            kind: ManagedProviderKind.subscriptionQuota,
            adapterId: 'official-codex-subscription',
          ),
        ],
      ),
    );
    usageCubit.emit(
      ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
    );

    await pumpPage(tester);

    expect(find.text('API balance · Example'), findsOneWidget);
    expect(find.text('Subscription quota · Codex'), findsOneWidget);
    expect(find.textContaining('official-codex-subscription'), findsNothing);
    expect(find.textContaining('apiBalance'), findsNothing);
    expect(
      find.byKey(const Key('managed-provider-actions-p1')),
      findsOneWidget,
    );
    expect(
      tester.widget(find.byKey(const Key('managed-provider-actions-p1'))),
      isA<Row>(),
    );
  });

  testWidgets(
    'embedded editor stays in the body and back returns to the provider list',
    (tester) async {
      providerCubit.emit(
        ManagedProviderState(status: ManagedProviderLoadStatus.ready),
      );
      usageCubit.emit(
        ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
      );
      await pumpPage(tester);
      final initialPushes = navigatorObserver.pushes;

      await tester.tap(find.byKey(const Key('managed-provider-add')));
      await tester.pumpAndSettle();

      expect(navigatorObserver.pushes, initialPushes);
      expect(
        find.byKey(const Key('managed-provider-management-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('managed-provider-editor-page')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('managed-provider-editor-back')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('managed-provider-editor-page')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('managed-provider-management-page')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'new editor applies the DeepSeek preset without inventing credentials',
    (tester) async {
      providerCubit.emit(
        ManagedProviderState(status: ManagedProviderLoadStatus.ready),
      );
      usageCubit.emit(
        ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
      );
      await pumpPage(tester);

      await openNewEditor(tester);
      await applyPreset(tester, 'DeepSeek');

      final nameInput = tester.widget<TpInputFormField>(
        find.byKey(const Key('managed-provider-name')),
      );
      expect(nameInput.controller!.text, 'DeepSeek');
      await tester.tap(find.byKey(const Key('managed-provider-section-query')));
      await tester.pumpAndSettle();
      final endpointInput = tester.widget<TpInputFormField>(
        find.byKey(const Key('managed-provider-endpoint')),
      );
      expect(
        endpointInput.controller!.text,
        'https://api.deepseek.com/user/balance',
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('managed-provider-section-display')),
        500,
        scrollable: _verticalScrollable(),
      );
      await tester.tap(
        find.byKey(const Key('managed-provider-section-display')),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('managed-provider-decimal-places')),
        500,
        scrollable: _verticalScrollable(),
      );
      final decimalsInput = tester.widget<TpInputFormField>(
        find.byKey(const Key('managed-provider-decimal-places')),
      );
      expect(decimalsInput.controller!.text, '2');
      final fieldMappings = tester.widget<TpTextareaFormField>(
        find.byKey(
          const Key('managed-provider-field-mappings'),
          skipOffstage: false,
        ),
      );
      expect(
        fieldMappings.controller!.text,
        contains(r'"currency": "$.currency"'),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('managed-provider-section-advanced')),
        500,
        scrollable: _verticalScrollable(),
      );
      await tester.tap(
        find.byKey(const Key('managed-provider-section-advanced')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      final credentialRefInput = tester.widget<TpInput>(
        find.byKey(
          const Key('managed-provider-credential-ref'),
          skipOffstage: false,
        ),
      );
      expect(credentialRefInput.controller!.text, isEmpty);
    },
  );

  testWidgets('preset schema controls visible editor sections', (tester) async {
    providerCubit.emit(
      ManagedProviderState(status: ManagedProviderLoadStatus.ready),
    );
    usageCubit.emit(
      ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
    );
    await pumpPage(tester);

    await openNewEditor(tester);
    await applyPreset(tester, 'Codex');

    expect(
      find.byKey(const Key('managed-provider-section-basics')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('managed-provider-section-query')),
      findsNothing,
    );
    expect(find.byKey(const Key('managed-provider-endpoint')), findsNothing);
    expect(
      find.byKey(const Key('managed-provider-section-credentials')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const Key('managed-provider-section-display'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const Key('managed-provider-section-advanced'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'Codex preset shows official login actions instead of an API key',
    (tester) async {
      providerCubit.emit(
        ManagedProviderState(status: ManagedProviderLoadStatus.ready),
      );
      usageCubit.emit(
        ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
      );
      await pumpPage(tester);

      await openNewEditor(tester);
      await applyPreset(tester, 'Codex');

      expect(
        find.byKey(const Key('managed-provider-official-credentials')),
        findsOneWidget,
      );
      expect(find.text('Sign in with OpenAI'), findsOneWidget);
      expect(
        find.byKey(const Key('managed-provider-credential-secret')),
        findsNothing,
      );
    },
  );

  testWidgets('DeepSeek preset starts with only required basics expanded', (
    tester,
  ) async {
    providerCubit.emit(
      ManagedProviderState(status: ManagedProviderLoadStatus.ready),
    );
    usageCubit.emit(
      ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
    );
    await pumpPage(tester);

    await openNewEditor(tester);
    await applyPreset(tester, 'DeepSeek');

    expect(
      find.byKey(const Key('managed-provider-section-basics')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('managed-provider-credential-secret')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('managed-provider-endpoint')), findsNothing);
    expect(
      find.byKey(const Key('managed-provider-field-mappings')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('managed-provider-credential-ref')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('managed-provider-decimal-places')),
      findsNothing,
    );
  });

  testWidgets('custom HTTP editors expand query setup by default', (
    tester,
  ) async {
    providerCubit.emit(
      ManagedProviderState(status: ManagedProviderLoadStatus.ready),
    );
    usageCubit.emit(
      ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
    );
    await pumpPage(tester);

    await openNewEditor(tester);

    expect(
      find.byKey(const Key('managed-provider-section-query')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('managed-provider-endpoint')), findsOneWidget);
  });

  testWidgets('preset selector stays searchable with the built-in presets', (
    tester,
  ) async {
    providerCubit.emit(
      ManagedProviderState(status: ManagedProviderLoadStatus.ready),
    );
    usageCubit.emit(
      ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
    );
    await pumpPage(tester);

    await openNewEditor(tester);
    await tester.tap(find.byKey(const Key('managed-provider-quick-preset')));
    await tester.pumpAndSettle();

    expect(find.byType(TpSelectSearchField), findsOneWidget);
    await tester.enterText(find.byType(TpSelectSearchField), 'Deep');
    await tester.pump();
    expect(find.text('DeepSeek'), findsWidgets);
    expect(find.text('Codex'), findsNothing);
  });

  testWidgets('new provider stores API key in secure storage only', (
    tester,
  ) async {
    providerCubit.emit(
      ManagedProviderState(status: ManagedProviderLoadStatus.ready),
    );
    usageCubit.emit(
      ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
    );
    await pumpPage(tester);

    await openNewEditor(tester);
    await applyPreset(tester, 'DeepSeek');
    await tester.enterText(
      find.byKey(const Key('managed-provider-credential-secret')),
      'sk-test-secret',
    );
    await _scrollToEditorBottom(tester);
    await tester.runAsync(() async {
      tester
          .widget<TpButton>(find.byKey(const Key('managed-provider-save')))
          .onPressed!
          .call();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    final provider = providerCubit.state.providers.single;
    expect(provider.credentialRef, 'managed-provider:${provider.id}');
    expect(provider.toJson().toString(), isNot(contains('sk-test-secret')));
    final scope = await ManagedProviderSecretStore(
      secureStore,
    ).read(provider.credentialRef!);
    expect(scope.valueFor('apiKey'), 'sk-test-secret');
  });

  testWidgets('DeepSeek preset requires an API key before save', (
    tester,
  ) async {
    providerCubit.emit(
      ManagedProviderState(status: ManagedProviderLoadStatus.ready),
    );
    usageCubit.emit(
      ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
    );
    await pumpPage(tester);

    await openNewEditor(tester);
    await applyPreset(tester, 'DeepSeek');
    await _scrollToEditorBottom(tester);
    await tester.runAsync(() async {
      tester
          .widget<TpButton>(find.byKey(const Key('managed-provider-save')))
          .onPressed!
          .call();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('managed-provider-editor-page')),
      findsOneWidget,
    );
    await _scrollToEditorTop(tester);
    expect(find.text('Provider credentials are missing.'), findsOneWidget);
    expect(providerCubit.state.providers, isEmpty);
    expect(httpJsonAdapter.calls, 0);
    expect(secureStore.values, isEmpty);
  });

  testWidgets('missing required secret focuses the credential field', (
    tester,
  ) async {
    providerCubit.emit(
      ManagedProviderState(status: ManagedProviderLoadStatus.ready),
    );
    usageCubit.emit(
      ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
    );
    await pumpPage(tester);

    await openNewEditor(tester);
    await applyPreset(tester, 'DeepSeek');
    await _scrollToEditorBottom(tester);
    await tester.runAsync(() async {
      tester
          .widget<TpButton>(find.byKey(const Key('managed-provider-save')))
          .onPressed!
          .call();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    final secretInput = tester.widget<TpInput>(
      find.byKey(const Key('managed-provider-credential-secret')),
    );
    expect(secretInput.focusNode?.hasFocus, isTrue);
  });

  testWidgets('first query runs after saving a new first-query preset', (
    tester,
  ) async {
    providerCubit.emit(
      ManagedProviderState(status: ManagedProviderLoadStatus.ready),
    );
    usageCubit.emit(
      ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
    );
    await pumpPage(tester);

    await openNewEditor(tester);
    await applyPreset(tester, 'DeepSeek');
    await tester.enterText(
      find.byKey(const Key('managed-provider-credential-secret')),
      'sk-test-secret',
    );
    await _scrollToEditorBottom(tester);
    await tester.runAsync(() async {
      tester
          .widget<TpButton>(find.byKey(const Key('managed-provider-save')))
          .onPressed!
          .call();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(httpJsonAdapter.calls, 1);
    expect(find.byKey(const Key('managed-provider-editor-page')), findsNothing);
    expect(find.text('12.50 USD'), findsOneWidget);
  });

  testWidgets(
    'first query failure preserves the saved provider and shows list error',
    (tester) async {
      providerCubit.emit(
        ManagedProviderState(status: ManagedProviderLoadStatus.ready),
      );
      usageCubit.emit(
        ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
      );
      httpJsonAdapter.error = const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.networkFailed,
      );
      await pumpPage(tester);

      await openNewEditor(tester);
      await applyPreset(tester, 'DeepSeek');
      await tester.enterText(
        find.byKey(const Key('managed-provider-credential-secret')),
        'sk-test-secret',
      );
      await _scrollToEditorBottom(tester);
      await tester.runAsync(() async {
        tester
            .widget<TpButton>(find.byKey(const Key('managed-provider-save')))
            .onPressed!
            .call();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(httpJsonAdapter.calls, 1);
      expect(providerCubit.state.providers, hasLength(1));
      expect(providerCubit.state.providers.single.name, 'DeepSeek');
      expect(
        find.byKey(const Key('managed-provider-query-error')),
        findsOneWidget,
      );
      expect(find.text('Provider network request failed.'), findsOneWidget);
      final provider = providerCubit.state.providers.single;
      final scope = await ManagedProviderSecretStore(
        secureStore,
      ).read(provider.credentialRef!);
      expect(scope.valueFor('apiKey'), 'sk-test-secret');
    },
  );

  testWidgets('editing with an empty API key preserves the existing secret', (
    tester,
  ) async {
    final existing = _provider().copyWith(
      credentialRef: 'managed-provider:p1',
      endpointConfig: ManagedProviderEndpointConfig(
        url: _provider().endpointConfig.url,
        credentialField: 'apiKey',
      ),
    );
    await ManagedProviderSecretStore(
      secureStore,
    ).write(existing.credentialRef!, {'apiKey': 'sk-existing'});
    providerCubit.emit(
      ManagedProviderState(
        status: ManagedProviderLoadStatus.ready,
        providers: [existing],
      ),
    );
    usageCubit.emit(
      ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
    );
    await pumpPage(tester);

    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('managed-provider-credential-secret')),
      500,
      scrollable: _verticalScrollable(),
    );
    expect(
      find.byKey(const Key('managed-provider-credential-secret')),
      findsOneWidget,
    );
    await _scrollToEditorBottom(tester);
    await tester.runAsync(() async {
      tester
          .widget<TpButton>(find.byKey(const Key('managed-provider-save')))
          .onPressed!
          .call();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    final saved = providerCubit.state.providers.single;
    expect(saved.credentialRef, existing.credentialRef);
    final scope = await ManagedProviderSecretStore(
      secureStore,
    ).read(existing.credentialRef!);
    expect(scope.valueFor('apiKey'), 'sk-existing');
  });

  testWidgets(
    'editing with an empty API key requires the existing stored secret',
    (tester) async {
      final existing = _provider().copyWith(
        credentialRef: 'managed-provider:p1',
        endpointConfig: ManagedProviderEndpointConfig(
          url: _provider().endpointConfig.url,
          credentialField: 'apiKey',
        ),
      );
      providerCubit.emit(
        ManagedProviderState(
          status: ManagedProviderLoadStatus.ready,
          providers: [existing],
        ),
      );
      usageCubit.emit(
        ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
      );
      await pumpPage(tester);

      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('managed-provider-credential-secret')),
        500,
        scrollable: _verticalScrollable(),
      );
      await tester.enterText(
        find.byKey(const Key('managed-provider-name')),
        'Changed Name',
      );
      await _scrollToEditorBottom(tester);
      await tester.runAsync(() async {
        tester
            .widget<TpButton>(find.byKey(const Key('managed-provider-save')))
            .onPressed!
            .call();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('managed-provider-editor-page')),
        findsOneWidget,
      );
      await _scrollToEditorTop(tester);
      expect(find.text('Provider credentials are missing.'), findsOneWidget);
      expect(providerCubit.state.providers.single.name, 'Example');
    },
  );

  testWidgets(
    'custom HTTP credentials reveal the secret field in the same editor session',
    (tester) async {
      providerCubit.emit(
        ManagedProviderState(status: ManagedProviderLoadStatus.ready),
      );
      usageCubit.emit(
        ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
      );
      await pumpPage(tester);

      await openNewEditor(tester);
      await tester.enterText(
        find.byKey(const Key('managed-provider-name')),
        'Custom',
      );
      await tester.enterText(
        find.byKey(const Key('managed-provider-endpoint')),
        'https://example.test/usage',
      );
      // Sections stay mounted (non-lazy editor scroll view), so bring the
      // credentials header into view directly and tap its visible header.
      final credentialsHeader = find.byKey(
        const Key('managed-provider-section-credentials'),
      );
      await tester.ensureVisible(credentialsHeader);
      await tester.pumpAndSettle();
      final viewport = tester.getRect(_verticalScrollable());
      if (!viewport.contains(tester.getCenter(credentialsHeader))) {
        await tester.drag(_verticalScrollable(), const Offset(0, -200));
        await tester.pumpAndSettle();
      }
      await tester.tap(credentialsHeader);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('managed-provider-credential-name')),
        'Authorization',
      );
      await tester.enterText(
        find.byKey(const Key('managed-provider-credential-field')),
        'apiKey',
      );
      await tester.pumpAndSettle();
      await _scrollToEditorTop(tester);

      expect(
        find.byKey(const Key('managed-provider-credential-secret')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('managed-provider-credential-secret')),
        'sk-custom',
      );
      await _scrollToEditorBottom(tester);
      await tester.runAsync(() async {
        tester
            .widget<TpButton>(find.byKey(const Key('managed-provider-save')))
            .onPressed!
            .call();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      final provider = providerCubit.state.providers.single;
      expect(provider.name, 'Custom');
      expect(provider.credentialRef, 'managed-provider:${provider.id}');
      expect(provider.toJson().toString(), isNot(contains('sk-custom')));
      final scope = await ManagedProviderSecretStore(
        secureStore,
      ).read(provider.credentialRef!);
      expect(scope.valueFor('apiKey'), 'sk-custom');
    },
  );

  testWidgets(
    'kind stays read-only for official presets and editable for custom HTTP',
    (tester) async {
      providerCubit.emit(
        ManagedProviderState(status: ManagedProviderLoadStatus.ready),
      );
      usageCubit.emit(
        ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
      );
      await pumpPage(tester);

      await openNewEditor(tester);
      await applyPreset(tester, 'Codex');
      await tester.scrollUntilVisible(
        find.byKey(const Key('managed-provider-section-advanced')),
        500,
        scrollable: _verticalScrollable(),
      );
      await tester.tap(
        find.byKey(const Key('managed-provider-section-advanced')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TpSelect<ManagedProviderKind>>(
              find.byKey(const Key('managed-provider-kind')),
            )
            .enabled,
        isFalse,
      );

      await tester.tap(find.byKey(const Key('managed-provider-editor-back')));
      await tester.pumpAndSettle();
      await openNewEditor(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('managed-provider-section-advanced')),
        500,
        scrollable: _verticalScrollable(),
      );
      await tester.tap(
        find.byKey(const Key('managed-provider-section-advanced')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TpSelect<ManagedProviderKind>>(
              find.byKey(const Key('managed-provider-kind')),
            )
            .enabled,
        isTrue,
      );
    },
  );

  testWidgets('advanced adapter input follows schema readOnly metadata', (
    tester,
  ) async {
    providerCubit.emit(
      ManagedProviderState(status: ManagedProviderLoadStatus.ready),
    );
    usageCubit.emit(
      ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
    );
    await pumpPage(tester);

    await openNewEditor(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('managed-provider-section-advanced')),
      500,
      scrollable: _verticalScrollable(),
    );
    await tester.tap(
      find.byKey(const Key('managed-provider-section-advanced')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TpInputFormField>(
            find.byKey(const Key('managed-provider-adapter')),
          )
          .readOnly,
      isFalse,
    );

    await tester.tap(find.byKey(const Key('managed-provider-editor-back')));
    await tester.pumpAndSettle();
    await openNewEditor(tester);
    await applyPreset(tester, 'Codex');
    await tester.scrollUntilVisible(
      find.byKey(const Key('managed-provider-section-advanced')),
      500,
      scrollable: _verticalScrollable(),
    );
    await tester.tap(
      find.byKey(const Key('managed-provider-section-advanced')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TpInputFormField>(
            find.byKey(const Key('managed-provider-adapter')),
          )
          .readOnly,
      isTrue,
    );
  });

  testWidgets(
    'CRUD actions are dispatched through the managed provider cubit',
    (tester) async {
      providerCubit.emit(
        ManagedProviderState(status: ManagedProviderLoadStatus.ready),
      );
      usageCubit.emit(
        ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
      );
      await pumpPage(tester);

      await tester.tap(find.byKey(const Key('managed-provider-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('managed-provider-name')),
        'New Provider',
      );
      await tester.enterText(
        find.byKey(const Key('managed-provider-endpoint')),
        'https://example.test/usage',
      );
      await tester.drag(_verticalScrollable(), const Offset(0, -800));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('managed-provider-save'), skipOffstage: false),
        500,
        scrollable: _verticalScrollable(),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('managed-provider-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 300));

      expect(providerCubit.state.providers.single.name, 'New Provider');
      expect(find.text('New Provider'), findsOneWidget);
    },
  );

  testWidgets('failed test query renders an explicit error state', (
    tester,
  ) async {
    await providerRepository.upsert(_provider());
    providerCubit.emit(
      ManagedProviderState(
        status: ManagedProviderLoadStatus.ready,
        providers: [_provider()],
      ),
    );
    usageCubit.emit(
      ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
    );
    await pumpPage(tester);
    adapter.error = const ManagedProviderUsageQueryError(
      ManagedProviderUsageQueryErrorCode.networkFailed,
    );

    await tester.tap(find.byKey(const Key('managed-provider-test-query')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(
      find.byKey(const Key('managed-provider-query-error')),
      findsOneWidget,
    );
  });

  testWidgets('editor test query does not overwrite the usage cache', (
    tester,
  ) async {
    await providerRepository.upsert(_provider());
    await usageRepository.save(_snapshot());
    final cacheBefore = fs.files['/tp/usage-cache.json'];
    adapter.result = Future.value(
      _snapshot().copyWith(
        measures: [
          ProviderUsageMeasure(
            label: 'Balance',
            kind: ProviderUsageMeasureKind.balance,
            remaining: '99.999999999999',
            unit: 'USD',
          ),
        ],
      ),
    );
    providerCubit.emit(
      ManagedProviderState(
        status: ManagedProviderLoadStatus.ready,
        providers: [_provider()],
      ),
    );
    usageCubit.emit(
      ManagedProviderUsageState(
        status: ManagedProviderUsageLoadStatus.ready,
        snapshots: {'p1': _snapshot()},
      ),
    );
    await pumpPage(tester);

    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    await _scrollToEditorBottom(tester);
    await tester.runAsync(() async {
      tester
          .widget<TpButton>(
            find.byKey(const Key('managed-provider-test-query')),
          )
          .onPressed!
          .call();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(fs.files['/tp/usage-cache.json'], cacheBefore);
    expect(
      (await usageRepository.load()).single.measures.single.remaining,
      '12.50',
    );
    expect(
      usageCubit.state.snapshotFor('p1')!.measures.single.remaining,
      '99.999999999999',
    );
  });

  testWidgets('editor save preserves unknown provider and endpoint fields', (
    tester,
  ) async {
    final existing = _provider().copyWith(
      unknownFields: {'providerExtension': 'keep'},
      endpointConfig: ManagedProviderEndpointConfig(
        url: 'https://example.test/usage',
        headers: {'X-Client': 'teampilot'},
        fieldMappings: {'remaining': r'$.balance'},
        unknownFields: {'endpointExtension': 'keep'},
      ),
    );
    await providerRepository.upsert(existing);
    providerCubit.emit(
      ManagedProviderState(
        status: ManagedProviderLoadStatus.ready,
        providers: [existing],
      ),
    );
    usageCubit.emit(
      ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
    );
    await pumpPage(tester);

    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    await _scrollToEditorBottom(tester);
    await tester.runAsync(() async {
      tester
          .widget<TpButton>(find.byKey(const Key('managed-provider-save')))
          .onPressed!
          .call();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    final saved = (await providerRepository.load()).single;
    expect(saved.endpointConfig.headers, {'X-Client': 'teampilot'});
    expect(saved.endpointConfig.fieldMappings, {'remaining': r'$.balance'});
    expect(saved.endpointConfig.unknownFields['endpointExtension'], 'keep');
    expect(saved.unknownFields['providerExtension'], 'keep');
  });

  testWidgets('editor rejects empty and public HTTP endpoints before save', (
    tester,
  ) async {
    providerCubit.emit(
      ManagedProviderState(status: ManagedProviderLoadStatus.ready),
    );
    usageCubit.emit(
      ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
    );
    await pumpPage(tester);
    await openNewEditor(tester);
    await tester.enterText(
      find.byKey(const Key('managed-provider-name')),
      'New Provider',
    );
    await _scrollToEditorBottom(tester);
    await tester.runAsync(() async {
      tester
          .widget<TpButton>(find.byKey(const Key('managed-provider-save')))
          .onPressed!
          .call();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await _scrollToEditorTop(tester);
    expect(
      find.text('Enter an HTTPS or loopback endpoint for this HTTP adapter.'),
      findsOneWidget,
    );
    expect(providerCubit.state.providers, isEmpty);

    await tester.enterText(
      find.byKey(const Key('managed-provider-endpoint')),
      'http://example.test/usage',
    );
    await _scrollToEditorBottom(tester);
    await tester.runAsync(() async {
      tester
          .widget<TpButton>(find.byKey(const Key('managed-provider-save')))
          .onPressed!
          .call();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await _scrollToEditorTop(tester);
    expect(
      find.text('Enter an HTTPS or loopback endpoint for this HTTP adapter.'),
      findsOneWidget,
    );
    expect(providerCubit.state.providers, isEmpty);
  });

  testWidgets('collapsed query section still blocks an invalid save', (
    tester,
  ) async {
    providerCubit.emit(
      ManagedProviderState(status: ManagedProviderLoadStatus.ready),
    );
    usageCubit.emit(
      ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
    );
    await pumpPage(tester);

    await openNewEditor(tester);
    await tester.enterText(
      find.byKey(const Key('managed-provider-name')),
      'Custom',
    );
    await tester.enterText(
      find.byKey(const Key('managed-provider-endpoint')),
      'http://example.test/usage',
    );
    await tester.pumpAndSettle();

    // Collapse the query section before saving. Tap the header list tile:
    // the shell's own center sits over the expanded section body.
    final queryHeader = find.byKey(const Key('managed-provider-section-query'));
    final queryTile = find.descendant(
      of: queryHeader,
      matching: find.byType(ListTile),
    );
    final viewport = tester.getRect(_verticalScrollable());
    if (!viewport.contains(tester.getCenter(queryTile))) {
      await tester.drag(_verticalScrollable(), const Offset(0, -200));
      await tester.pumpAndSettle();
    }
    await tester.tap(queryTile);
    await tester.pumpAndSettle();

    // Collapsed but still mounted: hidden on stage, present off stage.
    expect(
      find.byKey(const Key('managed-provider-endpoint')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('managed-provider-endpoint'), skipOffstage: false),
      findsOneWidget,
    );

    await _scrollToEditorBottom(tester);
    await tester.runAsync(() async {
      tester
          .widget<TpButton>(find.byKey(const Key('managed-provider-save')))
          .onPressed!
          .call();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(providerCubit.state.providers, isEmpty);
    expect(secureStore.values, isEmpty);
    expect(httpJsonAdapter.calls, 0);
    expect(
      find.byKey(const Key('managed-provider-editor-page')),
      findsOneWidget,
    );

    // Re-expanding surfaces the endpoint error from the collapsed section.
    await _scrollToEditorTop(tester);
    await tester.tap(queryTile);
    await tester.pumpAndSettle();
    expect(
      find.text('Enter an HTTPS or loopback endpoint for this HTTP adapter.'),
      findsOneWidget,
    );
  });

  testWidgets('list card shows brand mark and no wallet icon for Codex official', (
    tester,
  ) async {
    providerCubit.emit(
      ManagedProviderState(
        status: ManagedProviderLoadStatus.ready,
        providers: [
          ManagedProvider(
            id: 'p1',
            name: 'Codex',
            kind: ManagedProviderKind.subscriptionQuota,
            adapterId: 'official-codex-subscription',
          ),
        ],
      ),
    );
    usageCubit.emit(
      ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
    );

    await pumpPage(tester);

    expect(find.byKey(const Key('managed-provider-brand-p1')), findsOneWidget);
    expect(find.byIcon(Icons.account_balance_wallet_outlined), findsNothing);

    final icon = tester.getRect(find.byKey(const Key('managed-provider-brand-p1')));
    final name = tester.getRect(find.text('Codex').first);
    final subtitle = tester.getRect(find.text('Subscription quota · Codex'));
    final infoMidY = (name.top + subtitle.bottom) / 2;
    expect((icon.center.dy - infoMidY).abs(), lessThanOrEqualTo(1));
    final actions = tester.getRect(
      find.byKey(const Key('managed-provider-actions-p1')),
    );
    expect((actions.center.dy - infoMidY).abs(), lessThanOrEqualTo(1));
  });

  testWidgets('managed provider list and editor fit a 280dp viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    providerCubit.emit(
      ManagedProviderState(
        status: ManagedProviderLoadStatus.ready,
        providers: [_provider()],
      ),
    );
    usageCubit.emit(
      ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
    );

    await pumpPage(tester);
    expect(find.byKey(const Key('managed-provider-list')), findsOneWidget);
    // Narrow cards collapse actions into an overflow menu; open via the brand.
    await tester.tap(find.byKey(const Key('managed-provider-brand-p1')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('managed-provider-editor-error')),
      findsNothing,
    );
  });

  testWidgets(
    'enabled master switch is on basics without expanding advanced',
    (tester) async {
      providerCubit.emit(
        ManagedProviderState(status: ManagedProviderLoadStatus.ready),
      );
      usageCubit.emit(
        ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
      );
      await pumpPage(tester);

      await openNewEditor(tester);
      await applyPreset(tester, 'Codex');

      expect(
        find.byKey(const Key('managed-provider-kind')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('managed-provider-enabled')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const Key('managed-provider-enabled'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Turning this off hides this provider from the status bar and stops all querying.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Include this provider in refresh actions.'),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('managed-provider-enabled')));
      await tester.pumpAndSettle();
      await _scrollToEditorBottom(tester);
      await tester.runAsync(() async {
        tester
            .widget<TpButton>(find.byKey(const Key('managed-provider-save')))
            .onPressed!
            .call();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(providerCubit.state.providers, hasLength(1));
      expect(providerCubit.state.providers.single.enabled, isFalse);
      expect(
        find.byKey(
          Key('managed-provider-${providerCubit.state.providers.single.id}'),
        ),
        findsOneWidget,
      );
      expect(find.text('Disabled'), findsOneWidget);
    },
  );

  testWidgets('list pause disables provider without removing the card', (
    tester,
  ) async {
    providerCubit.emit(
      ManagedProviderState(
        status: ManagedProviderLoadStatus.ready,
        providers: [_provider()],
      ),
    );
    usageCubit.emit(
      ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
    );
    await pumpPage(tester);

    expect(find.byKey(const Key('managed-provider-p1')), findsOneWidget);
    expect(find.text('Enabled'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause_circle_outline));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    expect(providerCubit.state.providers.single.enabled, isFalse);
    expect(find.byKey(const Key('managed-provider-p1')), findsOneWidget);
    expect(find.text('Disabled'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
  });
}
