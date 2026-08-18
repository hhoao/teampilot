# Managed Provider Usage Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Build an independent Managed Provider catalog that securely queries API balances and subscription quotas, caches normalized snapshots, and exposes a desktop lower-left usage entry plus mobile Bottom Sheet.

**Architecture:** Keep ManagedProvider separate from CLI-scoped AppProviderConfig. Repositories own configuration and snapshots, a secure store owns credentials, an adapter registry normalizes provider-specific responses, and a coordinator/Cubit pair owns refresh state. AppShell injects the state once so pages and status-bar widgets never perform HTTP I/O.

**Tech Stack:** Flutter/Dart, flutter_bloc, equatable, AppStorage/Filesystem, existing SecureKeyValueStore, http, shared_ui TpPopover, GoRouter, ARB localization, Flutter widget tests.

## Global Constraints

- Do not modify the existing /providers/:cli Provider data structure or automatically inject Managed Providers into any CLI.
- ManagedProvider must not contain CliTool; future CLI association uses a separate binding model.
- API keys and OAuth tokens must not be serialized into Provider configuration, usage snapshots, logs, or Widget state.
- Use AppStorage/RuntimeContextRegistry paths and Filesystem; never use Directory.current for application data.
- Query failures preserve the last successful measure and must never render as a zero balance.
- All HTTP requests go through the adapter/coordinator layer; status-bar and page Widgets do not perform I/O.
- Use flutter_bloc for state; do not introduce provider or another state-management library.
- Add English and Simplified Chinese strings only to client/lib/l10n/app_en.arb and client/lib/l10n/app_zh.arb.
- New generic controls belong in client/packages/shared_ui; Managed Provider composition belongs under client/lib/pages/ and client/lib/widgets/.
- Before completion run cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration.

---

## File Map

New domain/storage:

- client/lib/models/managed_provider.dart
- client/lib/models/provider_usage_snapshot.dart
- client/lib/repositories/managed_provider_repository.dart
- client/lib/repositories/managed_provider_usage_repository.dart
- client/lib/services/provider_usage/managed_provider_secret_store.dart

New query/state:

- client/lib/services/provider_usage/managed_provider_usage_adapter.dart
- client/lib/services/provider_usage/managed_provider_usage_registry.dart
- client/lib/services/provider_usage/managed_provider_usage_coordinator.dart
- client/lib/services/provider_usage/adapters/http_json_mapping_adapter.dart
- client/lib/services/provider_usage/adapters/official_subscription_adapter.dart
- client/lib/cubits/managed_provider_cubit.dart
- client/lib/cubits/managed_provider_usage_cubit.dart

New UI:

- client/lib/pages/managed_providers/managed_provider_management_page.dart
- client/lib/pages/managed_providers/managed_provider_editor_page.dart
- client/lib/pages/managed_providers/managed_provider_list.dart
- client/lib/widgets/managed_provider/managed_provider_measure_view.dart
- client/lib/widgets/managed_provider/managed_provider_usage_panel.dart
- client/lib/widgets/managed_provider/managed_provider_usage_status_item.dart

Existing integration points:

- Modify client/lib/services/storage/app_storage.dart for managed-provider paths.
- Modify client/lib/app/app_shell.dart and client/lib/app/app_data_bootstrap.dart for global injection/loading.
- Modify HomeGlobalView files for the independent management page.
- Modify client/lib/widgets/workspace_status_bar/workspace_status_bar.dart and global_resource_manager_host.dart for the lower-left item.
- Modify client/lib/l10n/app_en.arb and app_zh.arb.

---

## Task 1: Add versioned domain models

Files:

- Create: client/lib/models/managed_provider.dart
- Create: client/lib/models/provider_usage_snapshot.dart
- Test: client/test/models/managed_provider_test.dart
- Test: client/test/models/provider_usage_snapshot_test.dart

Interfaces: Produce ManagedProvider, ManagedProviderKind, endpoint/display config types, ProviderUsageSnapshot, ProviderUsageMeasure, status/kind enums, and JSON helpers for all later tasks.

- [ ] Step 1: Write failing tests

~~~dart
test('ManagedProvider round-trips without a CLI field', () {
  const p = ManagedProvider(
    id: 'p1',
    name: 'Example',
    kind: ManagedProviderKind.apiBalance,
    adapterId: 'http-json',
    credentialRef: 'managed-provider:p1',
  );
  final json = p.toJson();
  expect(json.containsKey('cli'), isFalse);
  expect(ManagedProvider.fromJson(json), p);
});

test('stale snapshot retains measures and never serializes secrets', () {
  const snapshot = ProviderUsageSnapshot(
    providerId: 'p1',
    status: ProviderUsageStatus.stale,
    measures: [
      ProviderUsageMeasure(
        label: 'Balance',
        kind: ProviderUsageMeasureKind.balance,
        remaining: '12.50',
        unit: 'USD',
      ),
    ],
    fetchedAt: 100,
    staleAt: 200,
    lastErrorCode: 'networkFailed',
  );
  final json = snapshot.toJson();
  expect(json['measures'], isNotEmpty);
  expect(json.containsKey('apiKey'), isFalse);
  expect(ProviderUsageSnapshot.fromJson(json), snapshot);
});
~~~

Also cover unknown enum values, malformed individual measures, schema-version/unknown-field preservation, decimal-string amounts, and percentage clamping to 0–100.

- [ ] Step 2: Run and verify failure

Run: cd client && flutter test test/models/managed_provider_test.dart test/models/provider_usage_snapshot_test.dart

Expected: FAIL because the new types do not exist.

- [ ] Step 3: Implement models

Use immutable Equatable-compatible values, explicit toJson/fromJson, top-level schemaVersion, and unknownFields. Store monetary values as nullable decimal strings. Snapshot serialization must not accept or emit credential material.

- [ ] Step 4: Run the same command and verify PASS
- [ ] Step 5: Commit

~~~bash
git add client/lib/models/managed_provider.dart client/lib/models/provider_usage_snapshot.dart client/test/models/managed_provider_test.dart client/test/models/provider_usage_snapshot_test.dart
git commit -m "feat(provider-usage): add managed provider models"
~~~

## Task 2: Add configuration and usage-cache repositories

Files:

- Modify: client/lib/services/storage/app_storage.dart
- Create: client/lib/repositories/managed_provider_repository.dart
- Create: client/lib/repositories/managed_provider_usage_repository.dart
- Test: client/test/repositories/managed_provider_repository_test.dart
- Test: client/test/repositories/managed_provider_usage_repository_test.dart

Interfaces: Consume Task 1 models and injected Filesystem; produce CRUD methods load/save/upsert/delete for Providers and load/save/delete/clear for snapshots.

- [ ] Step 1: Write failing repository tests

Use the existing in-memory filesystem harness. Cover missing files, atomic parent-directory creation, malformed top-level JSON isolation, unknown-field preservation, Provider deletion cleanup, and this exact stale-cache behavior:

~~~dart
test('expired cache is returned as stale instead of discarded', () async {
  final repo = ManagedProviderUsageRepository(
    fs: fs,
    cachePath: '/tp/providers/managed/usage-cache.json',
    now: () => 300,
  );
  await repo.save(const ProviderUsageSnapshot(
    providerId: 'p1',
    status: ProviderUsageStatus.ready,
    measures: [],
    fetchedAt: 100,
    staleAt: 200,
  ));
  final result = await repo.load();
  expect(result.single.status, ProviderUsageStatus.stale);
  expect(result.single.fetchedAt, 100);
});
~~~

- [ ] Step 2: Run and verify failure

Run: cd client && flutter test test/repositories/managed_provider_repository_test.dart test/repositories/managed_provider_usage_repository_test.dart

Expected: FAIL because paths and repositories are missing.

- [ ] Step 3: Implement paths and repositories

Add managedProviderConfigFile and managedProviderUsageCacheFile under <teampilotRoot>/providers/managed/. Use injected Filesystem, atomicWrite, and partial-entry recovery; never use Directory.current.

- [ ] Step 4: Run the same command and verify PASS
- [ ] Step 5: Commit

~~~bash
git add client/lib/services/storage/app_storage.dart client/lib/repositories/managed_provider_repository.dart client/lib/repositories/managed_provider_usage_repository.dart client/test/repositories/managed_provider_repository_test.dart client/test/repositories/managed_provider_usage_repository_test.dart
git commit -m "feat(provider-usage): persist managed providers and snapshots"
~~~

## Task 3: Add secure credential references

Files:

- Create: client/lib/services/provider_usage/managed_provider_secret_store.dart
- Test: client/test/services/provider_usage/managed_provider_secret_store_test.dart

Interfaces: Consume ManagedProvider.credentialRef and existing SecureKeyValueStore; produce ManagedProviderSecretStore.read/write/delete and ManagedProviderCredentialResolver.resolve.

- [ ] Step 1: Write failing tests

Use a fake SecureKeyValueStore. Test namespacing, masked display values, read/write/delete, missing references, and that the model JSON never contains the secret value.

- [ ] Step 2: Run and verify failure

Run: cd client && flutter test test/services/provider_usage/managed_provider_secret_store_test.dart

Expected: FAIL because the store does not exist.

- [ ] Step 3: Implement the store

Use a fixed namespace such as teampilot.managed_provider.v1.<credentialRef>.<field>. Expose only request-scoped credentials to adapters. Do not include secret values in toString, exceptions, snapshots, or logger arguments. Keep the backend injectable for RuntimeContext-specific implementations.

- [ ] Step 4: Run the same command and verify PASS
- [ ] Step 5: Commit

~~~bash
git add client/lib/services/provider_usage/managed_provider_secret_store.dart client/test/services/provider_usage/managed_provider_secret_store_test.dart
git commit -m "feat(provider-usage): isolate managed provider credentials"
~~~

## Task 4: Add adapter contracts, registry, and HTTP JSON mapping

Files:

- Create: client/lib/services/provider_usage/managed_provider_usage_adapter.dart
- Create: client/lib/services/provider_usage/managed_provider_usage_registry.dart
- Create: client/lib/services/provider_usage/adapters/http_json_mapping_adapter.dart
- Test: client/test/services/provider_usage/http_json_mapping_adapter_test.dart

Interfaces: Produce ManagedProviderUsageAdapter, ProviderUsageHttpClient, ProviderCredentialResolver, ManagedProviderUsageRegistry, HttpJsonMappingAdapter, and typed query errors.

- [ ] Step 1: Write failing fixture tests

Use a fake HTTP client. Cover GET/POST, explicitly configured API-key placement, scalar and array JSON paths, decimal preservation, unit/currency, reset timestamps, missing fields, non-2xx, malformed JSON, and redacted errors:

~~~dart
test('maps multiple plans without converting decimal amounts to double', () async {
  final adapter = HttpJsonMappingAdapter(
    config: const HttpJsonMappingConfig(
      method: 'GET',
      url: 'https://example.test/v1/balance',
      measuresPath: r'$.data',
      labelPath: r'$.planName',
      remainingPath: r'$.remaining',
      totalPath: r'$.total',
      unitPath: r'$.unit',
    ),
  );
  final snapshot = await adapter.fetch(
    provider,
    credentials: resolver,
    http: fakeHttp,
    now: now,
  );
  expect(snapshot.measures.map((m) => m.remaining), ['12.50', '0.75']);
});
~~~

- [ ] Step 2: Run and verify failure

Run: cd client && flutter test test/services/provider_usage/http_json_mapping_adapter_test.dart

Expected: FAIL because the contracts and adapter do not exist.

- [ ] Step 3: Implement contracts, registry, and adapter

The registry rejects duplicate IDs and exposes register, adapterFor, and all. The mapping adapter validates HTTPS/loopback URL policy, constructs requests only through the injected client, parses configured paths, preserves decimal strings, and returns typed errors. It must not evaluate user code.

- [ ] Step 4: Run the same command and verify PASS
- [ ] Step 5: Commit

~~~bash
git add client/lib/services/provider_usage/managed_provider_usage_adapter.dart client/lib/services/provider_usage/managed_provider_usage_registry.dart client/lib/services/provider_usage/adapters/http_json_mapping_adapter.dart client/test/services/provider_usage/http_json_mapping_adapter_test.dart
git commit -m "feat(provider-usage): add extensible usage adapters"
~~~

## Task 5: Add official subscription boundary and refresh coordinator

Files:

- Create: client/lib/services/provider_usage/adapters/official_subscription_adapter.dart
- Create: client/lib/services/provider_usage/adapters/claude_subscription_adapter.dart
- Create: client/lib/services/provider_usage/adapters/codex_subscription_adapter.dart
- Create: client/lib/services/provider_usage/managed_provider_usage_coordinator.dart
- Test: client/test/services/provider_usage/managed_provider_usage_coordinator_test.dart
- Test: client/test/services/provider_usage/official_subscription_adapter_test.dart

Interfaces: Consume Tasks 2–4; produce OfficialSubscriptionAdapter, ClaudeSubscriptionAdapter, CodexSubscriptionAdapter, ManagedProviderUsageCoordinator.refreshOne, refreshAll, cancelForProvider, and refresh result/state contracts.

- [ ] Step 1: Write failing coordinator tests

Cover single-flight, refresh-all aggregation, generation-based old-result rejection, disabled/deleted Provider handling, preserving old measures on failures, and mapping missingCredential, authenticationFailed, networkFailed, httpFailed, responseParseFailed, and unsupported.

~~~dart
test('same Provider has at most one in-flight request', () async {
  final first = Completer<ProviderUsageSnapshot>();
  final adapter = BlockingFakeAdapter(first.future);
  final coordinator = buildCoordinator(adapter: adapter);
  final a = coordinator.refreshOne('p1');
  final b = coordinator.refreshOne('p1');
  expect(adapter.calls, 1);
  first.complete(readySnapshot);
  await Future.wait([a, b]);
});
~~~

- [ ] Step 2: Run and verify failure

Run: cd client && flutter test test/services/provider_usage/managed_provider_usage_coordinator_test.dart

Expected: FAIL because the coordinator is missing.

- [ ] Step 3: Implement coordinator and official boundary

Load cache before network work, mark expired entries stale, call the selected adapter, persist success, and persist stale/error snapshots retaining prior measures. Implement ClaudeSubscriptionAdapter and CodexSubscriptionAdapter behind stable adapter IDs using injected official-auth readers and normalized multi-window responses; they must not read CLI Provider lists or AppProviderConfig. Cover their response parsing and credential errors with fixture tests.

- [ ] Step 4: Run the same command and verify PASS
- [ ] Step 5: Commit

~~~bash
git add client/lib/services/provider_usage/adapters/official_subscription_adapter.dart client/lib/services/provider_usage/adapters/claude_subscription_adapter.dart client/lib/services/provider_usage/adapters/codex_subscription_adapter.dart client/lib/services/provider_usage/managed_provider_usage_coordinator.dart client/test/services/provider_usage/managed_provider_usage_coordinator_test.dart client/test/services/provider_usage/official_subscription_adapter_test.dart
git commit -m "feat(provider-usage): coordinate cached usage refreshes"
~~~

## Task 6: Add AppShell-scoped configuration and usage Cubits

Files:

- Create: client/lib/cubits/managed_provider_cubit.dart
- Create: client/lib/cubits/managed_provider_usage_cubit.dart
- Test: client/test/cubits/managed_provider_cubit_test.dart
- Test: client/test/cubits/managed_provider_usage_cubit_test.dart

Interfaces: Consume repositories and coordinator; produce load, add, update, delete, refreshOne, refreshAll, and ensureFresh actions with immutable state selectors.

- [ ] Step 1: Write failing Cubit tests

Test startup hydration, CRUD persistence, cached-first state, refresh transitions, retained measures on failure, disabled Provider exclusion, and duplicate ensureFresh calls.

- [ ] Step 2: Run and verify failure

Run: cd client && flutter test test/cubits/managed_provider_cubit_test.dart test/cubits/managed_provider_usage_cubit_test.dart

Expected: FAIL because the Cubits are missing.

- [ ] Step 3: Implement the Cubits

Keep configuration and usage states separate. Cubits dispatch to repositories/coordinator but never construct HTTP clients or parse responses. Emit per-provider status and global refresh state. On deletion, remove state after repository cleanup.

- [ ] Step 4: Run the same command and verify PASS
- [ ] Step 5: Commit

~~~bash
git add client/lib/cubits/managed_provider_cubit.dart client/lib/cubits/managed_provider_usage_cubit.dart client/test/cubits/managed_provider_cubit_test.dart client/test/cubits/managed_provider_usage_cubit_test.dart
git commit -m "feat(provider-usage): add managed provider state"
~~~

## Task 7: Wire AppShell bootstrap and reload lifecycle

Files:

- Modify: client/lib/app/app_shell.dart
- Modify: client/lib/app/app_data_bootstrap.dart
- Test: client/test/app/app_shell_provider_usage_bootstrap_test.dart

Interfaces: Consume Tasks 2–6; produce one global configuration Cubit and one usage Cubit reused by all workspaces and global pages.

- [ ] Step 1: Write failing bootstrap test

Inject fake repositories/coordinator into the AppShell seam and assert Cubits are available, configuration hydrates once, and reloadAllAppData reloads Providers without recreating usage state.

- [ ] Step 2: Run and verify failure

Run: cd client && flutter test test/app/app_shell_provider_usage_bootstrap_test.dart

Expected: FAIL because AppShell has no Managed Provider dependencies.

- [ ] Step 3: Wire dependencies

Construct repositories with AppStorage.fs and new AppPaths getters, construct the secret store with FlutterSecureKeyValueStore, register built-in adapters, create coordinator/Cubits, and add them to the existing app provider tree. Add load/reload calls to control-plane bootstrap; never create them per workspace tab.

- [ ] Step 4: Run the same command and verify PASS
- [ ] Step 5: Commit

~~~bash
git add client/lib/app/app_shell.dart client/lib/app/app_data_bootstrap.dart client/test/app/app_shell_provider_usage_bootstrap_test.dart
git commit -m "feat(provider-usage): bootstrap global usage state"
~~~

## Task 8: Build the independent Managed Provider management page

Files:

- Modify: client/lib/pages/home_workspace/home_workspace_global_section.dart
- Modify: client/lib/pages/home_workspace/home_workspace_sidebar.dart
- Modify: client/lib/pages/home_workspace/home_workspace_page.dart
- Modify: client/lib/pages/home_workspace/home_workspace_route.dart
- Create: client/lib/pages/managed_providers/managed_provider_management_page.dart
- Create: client/lib/pages/managed_providers/managed_provider_editor_page.dart
- Create: client/lib/pages/managed_providers/managed_provider_list.dart
- Create: client/lib/widgets/managed_provider/managed_provider_measure_view.dart
- Test: client/test/pages/managed_providers/managed_provider_management_page_test.dart
- Test: client/test/pages/home_workspace/home_managed_provider_route_test.dart

Interfaces: Consume both Cubits from Task 7; produce a CRUD page independent of LlmConfigWorkspace and /providers/:cli.

- [ ] Step 1: Write failing page/route tests

Test global=managedProviders resolves to the new page, global=providers still resolves to LlmConfigWorkspace, cached usage renders without network calls, CRUD dispatches expected Cubit actions, and failed test queries leave an explicit error state.

- [ ] Step 2: Run and verify failure

Run: cd client && flutter test test/pages/managed_providers/managed_provider_management_page_test.dart test/pages/home_workspace/home_managed_provider_route_test.dart

Expected: FAIL because the enum branch and pages are missing.

- [ ] Step 3: Implement page, editor, route, and sidebar entry

Add HomeGlobalView.managedProviders and its location, render it from HomeGlobalSection, add a separate sidebar entry, and leave the current CLI Providers entry unchanged. The editor supports kind, adapter, endpoint config, credential status, display config, test query, save, enable/disable, and delete. Use existing Tp form controls and AppToast; no I/O in build.

- [ ] Step 4: Run the same command and verify PASS
- [ ] Step 5: Commit

~~~bash
git add client/lib/pages/home_workspace/home_workspace_global_section.dart client/lib/pages/home_workspace/home_workspace_sidebar.dart client/lib/pages/home_workspace/home_workspace_page.dart client/lib/pages/home_workspace/home_workspace_route.dart client/lib/pages/managed_providers client/lib/widgets/managed_provider/managed_provider_measure_view.dart client/test/pages/managed_providers client/test/pages/home_workspace/home_managed_provider_route_test.dart
git commit -m "feat(provider-usage): add managed provider management page"
~~~

## Task 9: Add lower-left status item and usage panel

Files:

- Modify: client/lib/widgets/workspace_status_bar/workspace_status_bar.dart
- Modify: client/lib/pages/home_workspace/global_resource_manager_host.dart
- Create: client/lib/widgets/managed_provider/managed_provider_usage_status_item.dart
- Create: client/lib/widgets/managed_provider/managed_provider_usage_panel.dart
- Test: client/test/widgets/managed_provider/managed_provider_usage_status_item_test.dart
- Test: client/test/widgets/managed_provider/managed_provider_usage_panel_test.dart

Interfaces: Consume usage selectors/actions from Task 6 and management navigation from Task 8; produce a UI-only status item and 360px panel.

- [ ] Step 1: Write failing status-bar/panel tests

Cover empty state, one/multiple Provider summaries, stale/error warning, cached-first rendering, refresh action, management navigation, 360px width, and unchanged right-side item order:

~~~dart
testWidgets('usage item renders stale value and warning', (tester) async {
  await tester.pumpWidget(buildUsageHost(snapshot: staleSnapshot));
  expect(find.text('12.50 USD'), findsOneWidget);
  expect(find.byKey(const Key('managed-provider-usage-warning')), findsOneWidget);
});
~~~

- [ ] Step 2: Run and verify failure

Run: cd client && flutter test test/widgets/managed_provider/managed_provider_usage_status_item_test.dart test/widgets/managed_provider/managed_provider_usage_panel_test.dart

Expected: FAIL because the status item and leading group are missing.

- [ ] Step 3: Implement status-bar groups and panel

Extend WorkspaceStatusBar with optional leadingItems and trailingItems, preserving existing callers. Add the Managed Provider item to the leading group in GlobalResourceManagerHost. Use TpActionMenuAnchor and existing above-pill placement. The status item dispatches Cubit actions only; it never calls repositories or HTTP.

- [ ] Step 4: Run the same command and verify PASS
- [ ] Step 5: Commit

~~~bash
git add client/lib/widgets/workspace_status_bar/workspace_status_bar.dart client/lib/pages/home_workspace/global_resource_manager_host.dart client/lib/widgets/managed_provider/managed_provider_usage_status_item.dart client/lib/widgets/managed_provider/managed_provider_usage_panel.dart client/test/widgets/managed_provider
git commit -m "feat(provider-usage): add lower-left usage entry"
~~~

## Task 10: Add mobile launcher, localization, accessibility, and full verification

Files:

- Modify: client/lib/pages/home_workspace/home_workspace_sidebar.dart
- Modify: client/lib/widgets/managed_provider/managed_provider_usage_panel.dart
- Modify: client/lib/l10n/app_en.arb
- Modify: client/lib/l10n/app_zh.arb
- Test: client/test/pages/home_workspace/home_sidebar_managed_provider_test.dart
- Test: client/test/widgets/managed_provider/managed_provider_usage_panel_test.dart

- [ ] Step 1: Write failing mobile/localization tests

Assert mobile Home Sidebar/Footer opens the Bottom Sheet, desktop status-bar code is not mounted in mobile layout, every new button has localized text, and warning/error states have semantic labels.

- [ ] Step 2: Run and verify failure

Run: cd client && flutter test test/pages/home_workspace/home_sidebar_managed_provider_test.dart test/widgets/managed_provider/managed_provider_usage_panel_test.dart

Expected: FAIL because the launcher and keys are missing.

- [ ] Step 3: Implement mobile parity and copy

Add matching English/Chinese ARB keys, run flutter gen-l10n, use context.l10n, add stable test Keys and semantic labels for refresh, stale data, warnings, Provider rows, and navigation. Reuse the same Cubits and panel; do not create a second query path.

- [ ] Step 4: Run focused feature tests

~~~bash
cd client && flutter test test/models/managed_provider_test.dart test/models/provider_usage_snapshot_test.dart test/repositories/managed_provider_repository_test.dart test/repositories/managed_provider_usage_repository_test.dart test/services/provider_usage test/cubits/managed_provider_cubit_test.dart test/cubits/managed_provider_usage_cubit_test.dart test/pages/managed_providers test/widgets/managed_provider
~~~

Expected: all feature tests PASS.

- [ ] Step 5: Run regression tests

~~~bash
cd client && flutter test test/cubits/app_provider_cubit_test.dart test/pages/home_workspace test/widgets/workspace_status_bar test/pages/llm_config
~~~

Expected: existing CLI Provider, HomeShell, status-bar, and LLM configuration tests PASS unchanged.

- [ ] Step 6: Run analyzer and non-integration suite

~~~bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
~~~

Expected: analyzer exits 0 and the non-integration suite passes.

- [ ] Step 7: Commit

~~~bash
git add client/lib/pages/home_workspace/home_workspace_sidebar.dart client/lib/widgets/managed_provider/managed_provider_usage_panel.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/pages/home_workspace/home_sidebar_managed_provider_test.dart client/test/widgets/managed_provider/managed_provider_usage_panel_test.dart
git commit -m "feat(provider-usage): add mobile entry and localized copy"
~~~

- [ ] Step 8: Inspect final diff

~~~bash
git diff --check
git status --short
~~~

Expected: no whitespace errors; unrelated existing worktree changes remain untouched.
