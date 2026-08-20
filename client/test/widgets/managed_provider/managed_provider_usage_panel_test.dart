import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/managed_provider_cubit.dart';
import 'package:teampilot/cubits/managed_provider_usage_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_usage_repository.dart';
import 'package:teampilot/services/provider_usage/managed_provider_secret_store.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_coordinator.dart'
    show ManagedProviderUsageCoordinator;
import 'package:teampilot/services/provider_usage/managed_provider_usage_registry.dart';
import 'package:teampilot/widgets/managed_provider/managed_provider_usage_panel.dart';

import '../../support/in_memory_filesystem.dart';

ManagedProvider _provider({String id = 'p1', String name = 'Example'}) =>
    ManagedProvider(
      id: id,
      name: name,
      kind: ManagedProviderKind.apiBalance,
      adapterId: 'fake',
    );

ProviderUsageSnapshot _snapshot({
  String id = 'p1',
  ProviderUsageStatus status = ProviderUsageStatus.ready,
}) => ProviderUsageSnapshot(
  providerId: id,
  status: status,
  measures: [
    ProviderUsageMeasure(
      label: 'Balance',
      kind: ProviderUsageMeasureKind.balance,
      remaining: '8.00',
      unit: 'USD',
    ),
  ],
  fetchedAt: 100,
  staleAt: 1_000,
  lastErrorMessage: status == ProviderUsageStatus.error ? 'network' : null,
);

class _Adapter implements ManagedProviderUsageAdapter {
  @override
  String get id => 'fake';

  @override
  Future<ProviderUsageSnapshot> fetch(
    ManagedProvider provider, {
    required ProviderCredentialResolver credentials,
    required ProviderUsageHttpClient http,
    required DateTime now,
  }) async => _snapshot(id: provider.id);
}

class _NoCredentials implements ProviderCredentialResolver {
  @override
  Future<ProviderCredentialScope> resolve(ManagedProvider provider) async =>
      ManagedProviderCredentialScope(const {});
}

class _NoHttp implements ProviderUsageHttpClient {
  @override
  Future<ProviderUsageHttpResponse> send(ProviderUsageHttpRequest request) =>
      Future.error(StateError('HTTP should be owned by the adapter'));
}

ManagedProvider _codexProvider() => ManagedProvider(
  id: 'p1',
  name: 'Codex',
  kind: ManagedProviderKind.subscriptionQuota,
  adapterId: 'official-codex-subscription',
);

void main() {
  testWidgets('panel row shows brand mark key and no wallet icon', (
    tester,
  ) async {
    final fs = InMemoryFilesystem();
    final usage = ManagedProviderUsageRepository(
      fs: fs,
      cachePath: '/tp/usage-cache.json',
      now: () => 100,
    );
    final providers = ManagedProviderRepository(
      fs: fs,
      configPath: '/tp/providers.json',
      onProvidersDeleted: usage.deleteMany,
    );
    final coordinator = ManagedProviderUsageCoordinator(
      providerRepository: providers,
      usageRepository: usage,
      registry: ManagedProviderUsageRegistry([_Adapter()]),
      credentials: _NoCredentials(),
      http: _NoHttp(),
    );
    final providerCubit = ManagedProviderCubit(repository: providers)
      ..emit(
        ManagedProviderState(
          status: ManagedProviderLoadStatus.ready,
          providers: [_codexProvider()],
        ),
      );
    final usageCubit = ManagedProviderUsageCubit(coordinator: coordinator)
      ..emit(
        ManagedProviderUsageState(
          status: ManagedProviderUsageLoadStatus.ready,
          snapshots: {},
        ),
      );
    addTearDown(providerCubit.close);
    addTearDown(usageCubit.close);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: providerCubit),
            BlocProvider.value(value: usageCubit),
          ],
          child: const Scaffold(body: ManagedProviderUsagePanel()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('managed-provider-brand-p1')), findsOneWidget);
    expect(find.byIcon(Icons.account_balance_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panel omits disabled providers from the list', (
    tester,
  ) async {
    final fs = InMemoryFilesystem();
    final usage = ManagedProviderUsageRepository(
      fs: fs,
      cachePath: '/tp/usage-cache.json',
      now: () => 100,
    );
    final providers = ManagedProviderRepository(
      fs: fs,
      configPath: '/tp/providers.json',
      onProvidersDeleted: usage.deleteMany,
    );
    final coordinator = ManagedProviderUsageCoordinator(
      providerRepository: providers,
      usageRepository: usage,
      registry: ManagedProviderUsageRegistry([_Adapter()]),
      credentials: _NoCredentials(),
      http: _NoHttp(),
    );
    final disabledProvider = ManagedProvider(
      id: 'p2',
      name: 'Disabled',
      kind: ManagedProviderKind.apiBalance,
      adapterId: 'fake',
      enabled: false,
    );
    final providerCubit = ManagedProviderCubit(repository: providers)
      ..emit(
        ManagedProviderState(
          status: ManagedProviderLoadStatus.ready,
          providers: [_provider(), disabledProvider],
        ),
      );
    final usageCubit = ManagedProviderUsageCubit(coordinator: coordinator)
      ..emit(
        ManagedProviderUsageState(
          status: ManagedProviderUsageLoadStatus.ready,
          snapshots: {},
        ),
      );
    addTearDown(providerCubit.close);
    addTearDown(usageCubit.close);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: providerCubit),
            BlocProvider.value(value: usageCubit),
          ],
          child: const Scaffold(body: ManagedProviderUsagePanel()),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('managed-provider-usage-row-p1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('managed-provider-usage-row-p2')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('panel shows stale/error states while retaining measure values', (
    tester,
  ) async {
    final fs = InMemoryFilesystem();
    final usage = ManagedProviderUsageRepository(
      fs: fs,
      cachePath: '/tp/usage-cache.json',
      now: () => 100,
    );
    final providers = ManagedProviderRepository(
      fs: fs,
      configPath: '/tp/providers.json',
      onProvidersDeleted: usage.deleteMany,
    );
    final coordinator = ManagedProviderUsageCoordinator(
      providerRepository: providers,
      usageRepository: usage,
      registry: ManagedProviderUsageRegistry([_Adapter()]),
      credentials: _NoCredentials(),
      http: _NoHttp(),
    );
    final providerCubit = ManagedProviderCubit(repository: providers)
      ..emit(
        ManagedProviderState(
          status: ManagedProviderLoadStatus.ready,
          providers: [_provider()],
        ),
      );
    final usageCubit = ManagedProviderUsageCubit(coordinator: coordinator)
      ..emit(
        ManagedProviderUsageState(
          status: ManagedProviderUsageLoadStatus.ready,
          snapshots: {'p1': _snapshot(status: ProviderUsageStatus.error)},
        ),
      );
    addTearDown(providerCubit.close);
    addTearDown(usageCubit.close);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: providerCubit),
            BlocProvider.value(value: usageCubit),
          ],
          child: const Scaffold(body: ManagedProviderUsagePanel()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('8.00 USD'), findsOneWidget);
    expect(
      find.byKey(const Key('managed-provider-usage-error')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('managed-provider-usage-row-p1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'usage row compact switch disables the provider and hides the row',
    (tester) async {
      final fs = InMemoryFilesystem();
      final usage = ManagedProviderUsageRepository(
        fs: fs,
        cachePath: '/tp/usage-cache.json',
        now: () => 100,
      );
      final providers = ManagedProviderRepository(
        fs: fs,
        configPath: '/tp/providers.json',
        onProvidersDeleted: usage.deleteMany,
      );
      final coordinator = ManagedProviderUsageCoordinator(
        providerRepository: providers,
        usageRepository: usage,
        registry: ManagedProviderUsageRegistry([_Adapter()]),
        credentials: _NoCredentials(),
        http: _NoHttp(),
      );
      final providerCubit = ManagedProviderCubit(repository: providers)
        ..emit(
          ManagedProviderState(
            status: ManagedProviderLoadStatus.ready,
            providers: [_provider()],
          ),
        );
      final usageCubit = ManagedProviderUsageCubit(coordinator: coordinator)
        ..emit(
          ManagedProviderUsageState(
            status: ManagedProviderUsageLoadStatus.ready,
            snapshots: {},
          ),
        );
      addTearDown(providerCubit.close);
      addTearDown(usageCubit.close);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: providerCubit),
              BlocProvider.value(value: usageCubit),
            ],
            child: const Scaffold(body: ManagedProviderUsagePanel()),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('managed-provider-usage-row-p1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('managed-provider-usage-enabled-p1')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('managed-provider-usage-enabled-p1')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(providerCubit.state.providers.single.enabled, isFalse);
      expect(
        find.byKey(const Key('managed-provider-usage-row-p1')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('managed-provider-usage-enabled-p1')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
