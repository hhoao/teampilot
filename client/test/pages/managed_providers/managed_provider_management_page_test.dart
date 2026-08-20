import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/managed_provider_cubit.dart';
import 'package:teampilot/cubits/managed_provider_usage_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/pages/managed_providers/managed_provider_management_page.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_usage_repository.dart';
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
  await tester.drag(_verticalScrollable(), const Offset(0, -800));
  await tester.pump();
}

Future<void> _scrollToEditorTop(WidgetTester tester) async {
  tester.binding.focusManager.primaryFocus?.unfocus();
  await tester.pump();
  await tester.drag(_verticalScrollable(), const Offset(0, 1000));
  await tester.pump();
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
  late _Adapter adapter;
  late _Adapter httpJsonAdapter;
  late _RecordingNavigatorObserver navigatorObserver;
  late _MemorySecureKeyValueStore secureStore;

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
    final coordinator = ManagedProviderUsageCoordinator(
      providerRepository: providerRepository,
      usageRepository: usageRepository,
      registry: ManagedProviderUsageRegistry([adapter, httpJsonAdapter]),
      credentials: _NoCredentials(),
      http: _NoHttp(),
      now: () => DateTime.fromMillisecondsSinceEpoch(100),
    );
    providerCubit = ManagedProviderCubit(repository: providerRepository);
    usageCubit = ManagedProviderUsageCubit(coordinator: coordinator);
  });

  tearDown(() async {
    await providerCubit.close();
    await usageCubit.close();
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
              BlocProvider(create: (_) => LayoutCubit()),
              RepositoryProvider.value(
                value: ManagedProviderSecretStore(secureStore),
              ),
            ],
            child: const Scaffold(
              body: ManagedProviderManagementPage(embedded: true),
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

      final nameInput = tester.widget<TpInput>(
        find.byKey(const Key('managed-provider-name')),
      );
      expect(nameInput.controller!.text, 'DeepSeek');
      await tester.tap(find.byKey(const Key('managed-provider-section-query')));
      await tester.pumpAndSettle();
      final endpointInput = tester.widget<TpInput>(
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
      final decimalsInput = tester.widget<TpInput>(
        find.byKey(const Key('managed-provider-decimal-places')),
      );
      expect(decimalsInput.controller!.text, '2');
      final fieldMappings = tester.widget<TpTextarea>(
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
      find.byKey(const Key('managed-provider-section-display')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('managed-provider-section-advanced')),
      findsOneWidget,
    );
  });

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

  testWidgets('custom HTTP presets expand query setup by default', (
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
    await applyPreset(tester, 'OpenCode');

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
    expect(find.text('OpenCode'), findsNothing);
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
      await applyPreset(tester, 'OpenCode');
      await tester.enterText(
        find.byKey(const Key('managed-provider-endpoint')),
        'https://example.test/usage',
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('managed-provider-section-credentials')),
        500,
        scrollable: _verticalScrollable(),
      );
      await tester.tap(
        find.byKey(const Key('managed-provider-section-credentials')),
      );
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
      expect(provider.name, 'OpenCode');
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
      await applyPreset(tester, 'OpenCode');
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
          .widget<TpInput>(find.byKey(const Key('managed-provider-adapter')))
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
          .widget<TpInput>(find.byKey(const Key('managed-provider-adapter')))
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
      await tester.drag(find.byType(ListView).last, const Offset(0, -800));
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
}
