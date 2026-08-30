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
import 'package:teampilot/widgets/managed_provider/managed_provider_usage_status_item.dart';
import 'package:teampilot/widgets/workspace_status_bar/workspace_status_bar.dart';

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
  String id = 'p1',
  ProviderUsageStatus status = ProviderUsageStatus.ready,
}) => ProviderUsageSnapshot(
  providerId: id,
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
  staleAt: status == ProviderUsageStatus.stale ? 1 : 1_000,
  lastErrorMessage: status == ProviderUsageStatus.error
      ? 'Unable to query provider usage.'
      : null,
);

class _Adapter implements ManagedProviderUsageAdapter {
  _Adapter(this.result);

  Future<ProviderUsageSnapshot> result;
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
    return Future.error(StateError('HTTP should be owned by the adapter'));
  }
}

void main() {
  late InMemoryFilesystem fs;
  late ManagedProviderRepository providers;
  late ManagedProviderCubit providerCubit;
  late ManagedProviderUsageCubit usageCubit;
  late _Adapter adapter;

  setUp(() async {
    fs = InMemoryFilesystem();
    final usage = ManagedProviderUsageRepository(
      fs: fs,
      cachePath: '/tp/usage-cache.json',
      now: () => 100,
    );
    providers = ManagedProviderRepository(
      fs: fs,
      configPath: '/tp/providers.json',
      onProvidersDeleted: usage.deleteMany,
    );
    adapter = _Adapter(Future.value(_snapshot()));
    final coordinator = ManagedProviderUsageCoordinator(
      providerRepository: providers,
      usageRepository: usage,
      registry: ManagedProviderUsageRegistry([adapter]),
      credentials: _NoCredentials(),
      http: _NoHttp(),
      now: () => DateTime.fromMillisecondsSinceEpoch(100),
    );
    await providers.upsert(_provider());
    providerCubit = ManagedProviderCubit(repository: providers);
    usageCubit = ManagedProviderUsageCubit(coordinator: coordinator);
  });

  tearDown(() async {
    await providerCubit.close();
    await usageCubit.close();
  });

  Future<void> pumpItem(
    WidgetTester tester, {
    required Iterable<ManagedProvider> providers,
    required Map<String, ProviderUsageSnapshot> snapshots,
    VoidCallback? onManage,
    ManagedProviderUsageLoadStatus usageStatus =
        ManagedProviderUsageLoadStatus.ready,
    bool isRefreshing = false,
  }) async {
    providerCubit.emit(
      ManagedProviderState(
        status: ManagedProviderLoadStatus.ready,
        providers: providers,
      ),
    );
    usageCubit.emit(
      ManagedProviderUsageState(
        status: usageStatus,
        snapshots: snapshots,
        isRefreshing: isRefreshing,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: providerCubit),
            BlocProvider.value(value: usageCubit),
          ],
          child: Scaffold(
            body: WorkspaceStatusBar(
              leadingItems: [
                ManagedProviderUsageStatusItem(onManage: onManage),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'two enabled providers show one focused brand and usage, not icon row',
    (tester) async {
      final codex = ManagedProvider(
        id: 'p1',
        name: 'Codex',
        kind: ManagedProviderKind.subscriptionQuota,
        adapterId: 'http-json',
        endpointConfig: ManagedProviderEndpointConfig(
          url: 'https://chatgpt.com/backend-api/wham/usage',
        ),
      );
      final claude = ManagedProvider(
        id: 'p2',
        name: 'Claude',
        kind: ManagedProviderKind.subscriptionQuota,
        adapterId: 'http-json',
        endpointConfig: ManagedProviderEndpointConfig(
          url: 'https://api.anthropic.com/api/oauth/usage',
        ),
      );
      await pumpItem(
        tester,
        providers: [codex, claude],
        snapshots: {
          'p1': ProviderUsageSnapshot(
            providerId: 'p1',
            status: ProviderUsageStatus.ready,
            fetchedAt: 100,
            measures: [
              ProviderUsageMeasure(
                label: 'Balance',
                kind: ProviderUsageMeasureKind.balance,
                remaining: '12.50',
                unit: 'USD',
              ),
            ],
          ),
          'p2': ProviderUsageSnapshot(
            providerId: 'p2',
            status: ProviderUsageStatus.ready,
            fetchedAt: 200,
            measures: [
              ProviderUsageMeasure(
                label: 'Balance',
                kind: ProviderUsageMeasureKind.balance,
                remaining: '99.00',
                unit: 'USD',
              ),
            ],
          ),
        },
      );

      expect(
        find.byKey(const Key('managed-provider-usage-brand-icons')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('managed-provider-brand-p2')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('managed-provider-brand-p1')), findsNothing);
      expect(find.text('99.00 USD'), findsOneWidget);
      expect(find.text('2'), findsNothing);
      expect(find.byIcon(Icons.account_balance_wallet_outlined), findsNothing);
    },
  );

  testWidgets('focus follows last changed provider across refreshes', (
    tester,
  ) async {
    final a = _provider(id: 'p1', name: 'A');
    final b = _provider(id: 'p2', name: 'B');
    await pumpItem(
      tester,
      providers: [a, b],
      snapshots: {
        'p1': ProviderUsageSnapshot(
          providerId: 'p1',
          status: ProviderUsageStatus.ready,
          fetchedAt: 100,
          measures: [
            ProviderUsageMeasure(
              label: 'Balance',
              kind: ProviderUsageMeasureKind.balance,
              remaining: '10',
              unit: 'USD',
            ),
          ],
        ),
        'p2': ProviderUsageSnapshot(
          providerId: 'p2',
          status: ProviderUsageStatus.ready,
          fetchedAt: 100,
          measures: [
            ProviderUsageMeasure(
              label: 'Balance',
              kind: ProviderUsageMeasureKind.balance,
              remaining: '20',
              unit: 'USD',
            ),
          ],
        ),
      },
    );
    // Cold start: equal fetchedAt → later list order → p2
    expect(find.byKey(const Key('managed-provider-brand-p2')), findsOneWidget);
    expect(find.text('20 USD'), findsOneWidget);

    usageCubit.emit(
      ManagedProviderUsageState(
        status: ManagedProviderUsageLoadStatus.ready,
        snapshots: {
          'p1': ProviderUsageSnapshot(
            providerId: 'p1',
            status: ProviderUsageStatus.ready,
            fetchedAt: 150,
            measures: [
              ProviderUsageMeasure(
                label: 'Balance',
                kind: ProviderUsageMeasureKind.balance,
                remaining: '9',
                unit: 'USD',
              ),
            ],
          ),
          'p2': ProviderUsageSnapshot(
            providerId: 'p2',
            status: ProviderUsageStatus.ready,
            fetchedAt: 100,
            measures: [
              ProviderUsageMeasure(
                label: 'Balance',
                kind: ProviderUsageMeasureKind.balance,
                remaining: '20',
                unit: 'USD',
              ),
            ],
          ),
        },
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('managed-provider-brand-p1')), findsOneWidget);
    expect(find.text('9 USD'), findsOneWidget);

    usageCubit.emit(
      ManagedProviderUsageState(
        status: ManagedProviderUsageLoadStatus.ready,
        snapshots: {
          'p1': ProviderUsageSnapshot(
            providerId: 'p1',
            status: ProviderUsageStatus.ready,
            fetchedAt: 150,
            measures: [
              ProviderUsageMeasure(
                label: 'Balance',
                kind: ProviderUsageMeasureKind.balance,
                remaining: '9',
                unit: 'USD',
              ),
            ],
          ),
          'p2': ProviderUsageSnapshot(
            providerId: 'p2',
            status: ProviderUsageStatus.ready,
            fetchedAt: 160,
            measures: [
              ProviderUsageMeasure(
                label: 'Balance',
                kind: ProviderUsageMeasureKind.balance,
                remaining: '19',
                unit: 'USD',
              ),
            ],
          ),
        },
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('managed-provider-brand-p2')), findsOneWidget);
    expect(find.text('19 USD'), findsOneWidget);
  });

  testWidgets(
    'one enabled provider shows single brand mark and no wallet icon',
    (tester) async {
      final codex = ManagedProvider(
        id: 'p1',
        name: 'Codex',
        kind: ManagedProviderKind.subscriptionQuota,
        adapterId: 'http-json',
        endpointConfig: ManagedProviderEndpointConfig(
          url: 'https://chatgpt.com/backend-api/wham/usage',
        ),
      );
      await pumpItem(tester, providers: [codex], snapshots: {});

      expect(
        find.byKey(const Key('managed-provider-brand-p1')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.account_balance_wallet_outlined), findsNothing);
      expect(
        find.byKey(const Key('managed-provider-usage-brand-icons')),
        findsNothing,
      );
      final icon = tester.getRect(
        find.byKey(const Key('managed-provider-brand-p1')),
      );
      final label = tester.getRect(
        find.byKey(const Key('managed-provider-usage-status-label')),
      );
      expect((icon.center.dy - label.center.dy).abs(), lessThanOrEqualTo(1));
    },
  );

  testWidgets(
    'loading with cached snapshots keeps brand marks instead of a spinner',
    (tester) async {
      final codex = ManagedProvider(
        id: 'p1',
        name: 'Codex',
        kind: ManagedProviderKind.subscriptionQuota,
        adapterId: 'http-json',
        endpointConfig: ManagedProviderEndpointConfig(
          url: 'https://chatgpt.com/backend-api/wham/usage',
        ),
      );
      await pumpItem(
        tester,
        providers: [codex],
        snapshots: {'p1': _snapshot()},
        usageStatus: ManagedProviderUsageLoadStatus.loading,
      );

      expect(
        find.byKey(const Key('managed-provider-brand-p1')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('disabled provider is omitted from the status segment', (
    tester,
  ) async {
    final enabled = _provider(id: 'p1');
    final disabled = ManagedProvider(
      id: 'p2',
      name: 'Disabled',
      kind: ManagedProviderKind.apiBalance,
      adapterId: 'fake',
      enabled: false,
      endpointConfig: ManagedProviderEndpointConfig(
        url: 'https://example.test/usage',
      ),
    );
    await pumpItem(tester, providers: [enabled, disabled], snapshots: {});

    expect(find.byKey(const Key('managed-provider-brand-p1')), findsOneWidget);
    expect(find.byKey(const Key('managed-provider-brand-p2')), findsNothing);
    expect(
      find.byKey(const Key('managed-provider-usage-brand-icons')),
      findsNothing,
    );
  });

  testWidgets('one enabled stale provider shows brand mark without warning', (
    tester,
  ) async {
    await pumpItem(
      tester,
      providers: [_provider()],
      snapshots: {'p1': _snapshot(status: ProviderUsageStatus.stale)},
    );

    expect(find.byKey(const Key('managed-provider-brand-p1')), findsOneWidget);
    expect(
      find.byKey(const Key('managed-provider-usage-warning')),
      findsNothing,
    );
  });

  testWidgets(
    'two enabled providers, focused one healthy, other stale shows no warning',
    (tester) async {
      final a = _provider(id: 'p1', name: 'A');
      final b = _provider(id: 'p2', name: 'B');
      await pumpItem(
        tester,
        providers: [a, b],
        snapshots: {
          // p1 has the later fetchedAt, so cold start focuses it even
          // though it is healthy; p2 (stale) stays off-screen.
          'p1': ProviderUsageSnapshot(
            providerId: 'p1',
            status: ProviderUsageStatus.ready,
            fetchedAt: 200,
            measures: [
              ProviderUsageMeasure(
                label: 'Balance',
                kind: ProviderUsageMeasureKind.balance,
                remaining: '12.50',
                unit: 'USD',
              ),
            ],
          ),
          'p2': _snapshot(id: 'p2', status: ProviderUsageStatus.stale),
        },
      );

      expect(
        find.byKey(const Key('managed-provider-brand-p1')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('managed-provider-brand-p2')), findsNothing);
      expect(
        find.byKey(const Key('managed-provider-usage-warning')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'focused healthy provider stays calm when another enabled provider errors',
    (tester) async {
      final a = _provider(id: 'p1', name: 'A');
      final b = _provider(id: 'p2', name: 'B');
      await pumpItem(
        tester,
        providers: [a, b],
        snapshots: {
          'p1': ProviderUsageSnapshot(
            providerId: 'p1',
            status: ProviderUsageStatus.ready,
            fetchedAt: 200,
            measures: [
              ProviderUsageMeasure(
                label: 'Balance',
                kind: ProviderUsageMeasureKind.balance,
                remaining: '12.50',
                unit: 'USD',
              ),
            ],
          ),
          'p2': _snapshot(id: 'p2', status: ProviderUsageStatus.error),
        },
      );

      expect(
        find.byKey(const Key('managed-provider-brand-p1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('managed-provider-usage-warning')),
        findsNothing,
      );
    },
  );

  testWidgets('focused error provider shows warning', (tester) async {
    final a = _provider(id: 'p1', name: 'A');
    final b = _provider(id: 'p2', name: 'B');
    await pumpItem(
      tester,
      providers: [a, b],
      snapshots: {
        'p1': _snapshot(id: 'p1', status: ProviderUsageStatus.error),
        'p2': ProviderUsageSnapshot(
          providerId: 'p2',
          status: ProviderUsageStatus.ready,
          fetchedAt: 50,
          measures: [
            ProviderUsageMeasure(
              label: 'Balance',
              kind: ProviderUsageMeasureKind.balance,
              remaining: '1',
              unit: 'USD',
            ),
          ],
        ),
      },
    );

    // Cold start: p1 has later fetchedAt (100 default) than p2 (50) → focus p1
    // when both "change" from empty previous; equal absent→present uses list
    // order / fetchedAt. _snapshot uses fetchedAt 100; p2 is 50 → p1 focused.
    expect(find.byKey(const Key('managed-provider-brand-p1')), findsOneWidget);
    expect(
      find.byKey(const Key('managed-provider-usage-warning')),
      findsOneWidget,
    );
  });

  testWidgets('shows a cached stale value without warning or querying', (
    tester,
  ) async {
    await pumpItem(
      tester,
      providers: [_provider()],
      snapshots: {'p1': _snapshot(status: ProviderUsageStatus.stale)},
    );

    expect(find.text('12.50 USD'), findsWidgets);
    expect(
      find.byKey(const Key('managed-provider-usage-warning')),
      findsNothing,
    );
    expect(adapter.calls, 0);
  });

  testWidgets('opens a 360px panel with refresh and management actions', (
    tester,
  ) async {
    var manageCalls = 0;
    await pumpItem(
      tester,
      providers: [_provider()],
      snapshots: {'p1': _snapshot()},
      onManage: () => manageCalls++,
    );

    await tester.tap(
      find.byKey(const Key('managed-provider-usage-status-item')),
    );
    await tester.pump();
    expect(adapter.calls, 1);

    await tester.pumpAndSettle();

    final panel = tester.widget<SizedBox>(
      find.byKey(const Key('managed-provider-usage-panel')),
    );
    expect(panel.width, 360);
    expect(find.text('12.50 USD'), findsWidgets);

    await tester.tap(find.byKey(const Key('managed-provider-usage-refresh')));
    await tester.pump();
    expect(adapter.calls, 2);

    await tester.tap(find.byKey(const Key('managed-provider-usage-manage')));
    expect(manageCalls, 1);
  });

  testWidgets(
    'renders an explicit empty state and does not overflow narrowly',
    (tester) async {
      await pumpItem(tester, providers: const [], snapshots: const {});
      await tester.tap(
        find.byKey(const Key('managed-provider-usage-status-item')),
      );
      await tester.pumpAndSettle();

      expect(find.text('No managed providers'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keeps legacy items on the right of leading items', (
    tester,
  ) async {
    final leading = _ProbeItem('leading');
    final trailing = _ProbeItem('trailing');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceStatusBar(
            leadingItems: [leading],
            trailingItems: [trailing],
          ),
        ),
      ),
    );
    expect(
      tester.getCenter(find.byKey(const Key('status-probe-leading'))).dx,
      lessThan(
        tester.getCenter(find.byKey(const Key('status-probe-trailing'))).dx,
      ),
    );
  });
}

class _ProbeItem implements WorkspaceStatusBarItem {
  _ProbeItem(this.name);

  final String name;

  @override
  String get id => name;

  @override
  Widget buildSegment(BuildContext context, {required bool compact}) =>
      SizedBox(key: Key('status-probe-$name'), width: 20, height: 20);
}
