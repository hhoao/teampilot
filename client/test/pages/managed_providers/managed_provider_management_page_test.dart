import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/managed_provider_cubit.dart';
import 'package:teampilot/cubits/managed_provider_usage_cubit.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/pages/managed_providers/managed_provider_editor_page.dart';
import 'package:teampilot/pages/managed_providers/managed_provider_management_page.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_usage_repository.dart';
import 'package:teampilot/services/provider_usage/managed_provider_secret_store.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_coordinator.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_registry.dart';

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
  Object? failure;
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
    final failure = this.failure;
    if (failure != null) throw failure;
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

void main() {
  late InMemoryFilesystem fs;
  late ManagedProviderRepository providerRepository;
  late ManagedProviderUsageRepository usageRepository;
  late ManagedProviderCubit providerCubit;
  late ManagedProviderUsageCubit usageCubit;
  late ManagedProviderUsageCoordinator coordinator;
  late _Adapter adapter;

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
    coordinator = ManagedProviderUsageCoordinator(
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
    await coordinator.close();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.runAsync(providerCubit.load);
    await tester.runAsync(usageCubit.load);
    await tester.pumpWidget(
      MaterialApp(
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
            ],
            child: const Scaffold(
              body: ManagedProviderManagementPage(embedded: true),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> scrollToEditorControl(
    WidgetTester tester,
    Key key, {
    double delta = 400,
  }) async {
    final editorScrollable = find.descendant(
      of: find.byType(ManagedProviderEditorPage),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(key),
      delta,
      scrollable: editorScrollable.first,
    );
  }

  testWidgets('renders cached usage without starting a network query', (
    tester,
  ) async {
    await providerRepository.upsert(_provider());
    await usageRepository.save(_snapshot());

    await pumpPage(tester);

    expect(find.text('12.50 USD'), findsOneWidget);
    expect(adapter.calls, 0);
  });

  testWidgets(
    'CRUD actions are dispatched through the managed provider cubit',
    (tester) async {
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
      await tester.scrollUntilVisible(
        find.byKey(const Key('managed-provider-save')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('managed-provider-save')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));

      expect(providerCubit.state.providers.single.name, 'New Provider');
      expect(find.text('New Provider'), findsOneWidget);
    },
  );

  testWidgets('failed test query renders an explicit error state', (
    tester,
  ) async {
    await providerRepository.upsert(_provider());
    await pumpPage(tester);
    adapter.failure = const ManagedProviderUsageQueryError(
      ManagedProviderUsageQueryErrorCode.networkFailed,
    );

    await tester.tap(find.byKey(const Key('managed-provider-test-query')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));

    expect(
      find.byKey(const Key('managed-provider-query-error')),
      findsOneWidget,
    );
    expect(find.textContaining('Unable to query'), findsOneWidget);
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
    await pumpPage(tester);

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await scrollToEditorControl(
      tester,
      const Key('managed-provider-test-query'),
    );
    await tester.tap(find.byKey(const Key('managed-provider-test-query')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));

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

  testWidgets(
    'editor preserves endpoint extensions and edits credential references',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await providerRepository.upsert(
        _provider().copyWith(
          credentialRef: 'managed-ref',
          unknownFields: {'providerExtension': 'keep'},
          endpointConfig: ManagedProviderEndpointConfig(
            url: 'https://example.test/usage',
            headers: {'X-Client': 'teampilot'},
            fieldMappings: {'remaining': r'$.balance'},
            credentialName: 'X-API-Key',
            credentialField: 'apiKey',
            credentialPlacement: 'header',
            unknownFields: {'endpointExtension': 'keep'},
          ),
        ),
      );
      await pumpPage(tester);

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      tester
              .widget<TpInput>(
                find.byKey(const Key('managed-provider-credential-ref')),
              )
              .controller!
              .text =
          'managed-ref-next';
      tester
              .widget<TpInput>(
                find.byKey(const Key('managed-provider-credential-name')),
              )
              .controller!
              .text =
          'Authorization';
      tester
              .widget<TpInput>(
                find.byKey(const Key('managed-provider-credential-field')),
              )
              .controller!
              .text =
          'accessToken';
      await tester.pump();
      await tester.tap(find.byKey(const Key('managed-provider-save')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));

      final saved = (await providerRepository.load()).single;
      expect(saved.credentialRef, 'managed-ref-next');
      expect(saved.endpointConfig.headers, {'X-Client': 'teampilot'});
      expect(saved.endpointConfig.fieldMappings, {'remaining': r'$.balance'});
      expect(saved.endpointConfig.unknownFields['endpointExtension'], 'keep');
      expect(saved.unknownFields['providerExtension'], 'keep');
      expect(saved.endpointConfig.credentialName, 'Authorization');
      expect(saved.endpointConfig.credentialField, 'accessToken');
    },
  );

  testWidgets('editor rejects empty and public HTTP endpoints before save', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('managed-provider-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('managed-provider-name')),
      'New Provider',
    );
    await scrollToEditorControl(tester, const Key('managed-provider-save'));
    await tester.tap(find.byKey(const Key('managed-provider-save')));
    await tester.pumpAndSettle();
    await scrollToEditorControl(
      tester,
      const Key('managed-provider-editor-error'),
      delta: -400,
    );
    expect(
      find.text('Endpoint URL is required for HTTP JSON providers.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('managed-provider-endpoint')),
      'http://example.test/usage',
    );
    await scrollToEditorControl(tester, const Key('managed-provider-save'));
    await tester.tap(find.byKey(const Key('managed-provider-save')));
    await tester.pumpAndSettle();
    await scrollToEditorControl(
      tester,
      const Key('managed-provider-editor-error'),
      delta: -400,
    );
    expect(
      find.text('Use an HTTPS endpoint, or an HTTP loopback endpoint.'),
      findsOneWidget,
    );
  });

  testWidgets('managed provider list and editor fit a 280dp viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await providerRepository.upsert(_provider());

    await pumpPage(tester);
    expect(find.byKey(const Key('managed-provider-list')), findsOneWidget);
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('managed-provider-editor-error')),
      findsNothing,
    );
  });
}
