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
  _Adapter(this.result);

  Future<ProviderUsageSnapshot> result;
  Object? error;
  int calls = 0;

  @override
  String get id => 'fake';

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
    navigatorObserver = _RecordingNavigatorObserver();
    secureStore = _MemorySecureKeyValueStore();
    final coordinator = ManagedProviderUsageCoordinator(
      providerRepository: providerRepository,
      usageRepository: usageRepository,
      registry: ManagedProviderUsageRegistry([adapter]),
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

      await tester.tap(find.byKey(const Key('managed-provider-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('managed-provider-quick-preset')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DeepSeek').last);
      await tester.pumpAndSettle();

      final nameInput = tester.widget<TpInput>(
        find.byKey(const Key('managed-provider-name')),
      );
      final endpointInput = tester.widget<TpInput>(
        find.byKey(const Key('managed-provider-endpoint')),
      );
      expect(nameInput.controller!.text, 'DeepSeek');
      expect(
        endpointInput.controller!.text,
        'https://api.deepseek.com/user/balance',
      );
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
      final credentialRefInput = tester.widget<TpInput>(
        find.byKey(
          const Key('managed-provider-credential-ref'),
          skipOffstage: false,
        ),
      );
      expect(credentialRefInput.controller!.text, isEmpty);
    },
  );

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

    await tester.tap(find.byKey(const Key('managed-provider-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('managed-provider-quick-preset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('managed-provider-credential-secret')),
      500,
      scrollable: _verticalScrollable(),
    );
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
