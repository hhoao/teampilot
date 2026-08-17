# API Model Catalogs for Codex and Claude Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add API-key-backed dynamic model catalogs for Codex/OpenAI and Claude/Anthropic, with safe cache and current static fallbacks for OAuth/offline use.

**Architecture:** A shared `ApiModelCatalogService` owns HTTP authentication, endpoint normalization, response parsing, per-provider memory state, disk cache, TTL, and notifications. Codex and Claude capabilities inject protocol-specific service instances and expose live IDs only for API-key providers; their static catalog sources remain the fallback. The existing model picker passes the complete provider record into refresh calls.

**Tech Stack:** Flutter/Dart, `package:http`, injected `http.Client`, TeamPilot `Filesystem`, `flutter/foundation.dart` `ChangeNotifier`, Flutter unit/widget tests.

## Global Constraints

- Preserve all existing uncommitted user changes; only touch files listed in this plan.
- Never persist or log API keys; cache only model IDs and fetch timestamps.
- OAuth/ChatGPT/Claude.ai providers must not trigger API model requests without an API key.
- Use `AppStorage`/injected `Filesystem` for cache paths; do not use `Directory.current`.
- Keep the existing `ProviderCapability`/CLI registry architecture; do not add CLI checks to pages or cubits.
- Write each behavior test before its production implementation and run the test to observe the expected failure.
- Final verification from `client/`: `flutter analyze --no-fatal-infos --no-fatal-warnings` and `flutter test --exclude-tags integration`.

---

### Task 1: Add the shared API model catalog service

**Files:**
- Create: `client/lib/services/provider/api_model_catalog_service.dart`
- Test: `client/test/services/provider/api_model_catalog_service_test.dart`

**Interfaces:**
- Consumes: `AppProviderConfig`, `Filesystem`, `AppStorage`, `http.Client`.
- Produces: `ApiModelCatalogProtocol`, `ApiModelCatalogService`, `ApiModelCatalogCacheEntry`.

- [ ] **Step 1: Write failing tests for the cache model and response parser**

Add tests with these exact behaviors:

```dart
test('parses model ids from API data, removes duplicates and blanks', () {
  final ids = ApiModelCatalogService.parseModelIds({
    'data': [
      {'id': ' model-b '},
      {'id': ''},
      {'id': 'model-a'},
      {'id': 'model-b'},
      {'name': 'missing-id'},
    ],
  });

  expect(ids, ['model-a', 'model-b']);
});

test('cache entry round trips only timestamp and model ids', () {
  const original = ApiModelCatalogCacheEntry(
    fetchedAtMs: 42,
    modelIds: ['model-a'],
  );

  expect(
    ApiModelCatalogCacheEntry.fromJson(original.toJson()).modelIds,
    ['model-a'],
  );
  expect(original.toJson().keys, containsAll(['fetchedAtMs', 'modelIds']));
  expect(original.toJson().keys, isNot(contains('apiKey')));
});
```

- [ ] **Step 2: Run the focused test and verify it fails for missing symbols**

Run: `cd client && flutter test test/services/provider/api_model_catalog_service_test.dart`

Expected: FAIL because `ApiModelCatalogService` and `ApiModelCatalogCacheEntry` do not exist yet.

- [ ] **Step 3: Implement the cache model and pure parser**

Define:

```dart
enum ApiModelCatalogProtocol { openAi, anthropic }

class ApiModelCatalogCacheEntry {
  const ApiModelCatalogCacheEntry({required this.fetchedAtMs, required this.modelIds});
  final int fetchedAtMs;
  final List<String> modelIds;
  Map<String, Object?> toJson();
  factory ApiModelCatalogCacheEntry.fromJson(Map<String, Object?> json);
}
```

`parseModelIds` must accept the normal `{data: [...]}` response and a top-level list, trim IDs, remove duplicates, and return lexicographically sorted IDs. Invalid shapes return an empty list.

- [ ] **Step 4: Add failing tests for endpoint and authentication resolution**

Use a `MockClient` that records the request and returns a valid model response:

```dart
test('OpenAI uses official v1 models endpoint and bearer auth', () async {
  late http.Request request;
  final service = ApiModelCatalogService(
    protocol: ApiModelCatalogProtocol.openAi,
    fs: InMemoryFilesystem(),
    basePath: '/data/tp',
    httpClient: MockClient((next) async {
      request = next;
      return http.Response('{"data":[{"id":"gpt-test"}]}', 200);
    }),
  );

  await service.ensureLoaded(
    providerId: 'openai-test',
    provider: const AppProviderConfig(
      id: 'openai-test',
      cli: CliTool.codex,
      name: 'OpenAI',
      apiKey: 'secret',
    ),
  );

  expect(request.url.toString(), 'https://api.openai.com/v1/models');
  expect(request.headers['authorization'], 'Bearer secret');
  expect(request.headers.containsKey('x-api-key'), isFalse);
});

test('Anthropic appends v1 models to a custom API root', () async {
  late http.Request request;
  final service = ApiModelCatalogService(
    protocol: ApiModelCatalogProtocol.anthropic,
    cacheDirectory: 'claude_models',
    fs: InMemoryFilesystem(),
    basePath: '/data/tp',
    httpClient: MockClient((next) async {
      request = next;
      return http.Response('{"data":[{"id":"claude-test"}]}', 200);
    }),
  );

  await service.ensureLoaded(
    providerId: 'anthropic-proxy',
    provider: const AppProviderConfig(
      id: 'anthropic-proxy',
      cli: CliTool.claude,
      name: 'Anthropic Proxy',
      apiKey: 'secret',
      baseUrl: 'https://proxy.example.test/anthropic',
    ),
  );

  expect(request.url.toString(), 'https://proxy.example.test/anthropic/v1/models');
  expect(request.headers['x-api-key'], 'secret');
  expect(request.headers['anthropic-version'], '2023-06-01');
});
```

- [ ] **Step 5: Run the focused tests and verify the request tests fail**

Run: `cd client && flutter test test/services/provider/api_model_catalog_service_test.dart`

Expected: FAIL because the service request implementation is not present.

- [ ] **Step 6: Implement endpoint resolution and authenticated fetching**

Implement `ensureLoaded({required String providerId, required AppProviderConfig provider, bool forceRefresh = false})`, `modelIdsFor({required String providerId})`, and `catalogUpdates`.

Rules:

- Empty `provider.apiKey` returns without a network request.
- OpenAI official default: `https://api.openai.com/v1/models`.
- Anthropic official default: `https://api.anthropic.com/v1/models`.
- A custom URL ending in `/models` is used as-is.
- A custom URL ending in `/v1` gets `/models`; other custom URLs get `/v1/models`.
- OpenAI sends `Authorization: Bearer <key>`.
- Anthropic sends `x-api-key: <key>` and `anthropic-version: 2023-06-01`.
- Requests time out after 10 seconds; non-200, invalid JSON, and empty ID lists are refresh misses.
- Coalesce concurrent refreshes per provider ID.

- [ ] **Step 7: Add failing tests for memory cache, disk cache, TTL, and failed refresh**

Cover these behaviors:

```dart
test('successful refresh writes cache and notifies listeners', () async {
  final service = makeService(response: '{"data":[{"id":"gpt-live"}]}');
  var notifications = 0;
  service.addListener(() => notifications++);

  await service.ensureLoaded(providerId: 'openai-test', provider: apiProvider);

  expect(service.modelIdsFor(providerId: 'openai-test'), ['gpt-live']);
  expect(notifications, greaterThan(0));
  expect(await readCache('openai-test'), isNotNull);
});

test('fresh disk cache avoids a network request', () async {
  await writeCache('openai-test', ['gpt-cached'], fresh: true);
  final service = makeService(response: '{"data":[{"id":"gpt-network"}]}');

  await service.ensureLoaded(providerId: 'openai-test', provider: apiProvider);

  expect(service.modelIdsFor(providerId: 'openai-test'), ['gpt-cached']);
  expect(requestCount, 0);
});

test('expired cache is replaced by a successful live response', () async {
  await writeCache('openai-test', ['gpt-old'], fresh: false);
  final service = makeService(response: '{"data":[{"id":"gpt-new"}]}');

  await service.ensureLoaded(providerId: 'openai-test', provider: apiProvider);

  expect(service.modelIdsFor(providerId: 'openai-test'), ['gpt-new']);
});

test('failed live refresh keeps a valid disk cache and does not throw', () async {
  await writeCache('openai-test', ['gpt-cached'], fresh: false);
  final service = makeService(statusCode: 503);

  await expectLater(
    service.ensureLoaded(providerId: 'openai-test', provider: apiProvider),
    completes,
  );

  expect(service.modelIdsFor(providerId: 'openai-test'), ['gpt-cached']);
});

test('missing API key skips network and leaves no live ids', () async {
  final service = makeService(response: '{"data":[{"id":"gpt-network"}]}');

  await service.ensureLoaded(
    providerId: 'openai-test',
    provider: apiProvider.copyWith(apiKey: ''),
  );

  expect(service.modelIdsFor(providerId: 'openai-test'), isEmpty);
  expect(requestCount, 0);
});
```

Use `InMemoryFilesystem`, fixed timestamps through cache fixtures, and `MockClient`; do not access real network or application storage.

- [ ] **Step 8: Run the focused tests and verify they fail before cache implementation**

Run: `cd client && flutter test test/services/provider/api_model_catalog_service_test.dart`

Expected: FAIL on service behavior assertions.

- [ ] **Step 9: Implement cache lifecycle and notifications**

Use cache paths `cache/<cacheDirectory>/<sanitizedProviderId>.json`, where the service receives `cacheDirectory` (`codex_models` or `claude_models`). Resolve injected test storage first, then `AppStorage.context`, then `AppStorage.fs`/`AppStorage.appDataRoot` as existing services do. Keep model IDs in memory before writing disk so a write failure does not discard a successful response. Notify listeners after loading disk or live data.

- [ ] **Step 10: Run focused service tests and refactor only after green**

Run: `cd client && flutter test test/services/provider/api_model_catalog_service_test.dart`

Expected: all service tests PASS. Refactor duplicated URL/parser/cache code only while this focused test remains green.

---

### Task 2: Wire provider configuration into refreshable capabilities

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/provider_capability.dart:561-566`
- Modify: `client/lib/widgets/app_provider/provider_model_picker_field.dart:49-81`
- Test: `client/test/widgets/app_provider/provider_model_picker_field_test.dart` (create if no existing file)

**Interfaces:**
- Consumes: `ApiModelCatalogService.ensureLoaded` provider argument.
- Produces: `refreshModelCatalog({String providerId, AppProviderConfig? provider, String? executable, bool forceRefresh})`.

- [ ] **Step 1: Add a failing test proving refresh receives the provider record**

Exercise the picker with a fake `RefreshableProviderModelCapability` and assert its refresh call receives the same `AppProviderConfig` instance, including `apiKey` and `baseUrl`.

- [ ] **Step 2: Run the focused widget test and verify it fails**

Run: `cd client && flutter test test/widgets/app_provider/provider_model_picker_field_test.dart`

Expected: FAIL because the picker currently calls refresh without `provider`.

- [ ] **Step 3: Extend the refresh interface and picker call**

Add `AppProviderConfig? provider` to the default interface method and pass `provider: widget.provider`. Reattach the refresh listener when the provider's ID, CLI, base URL, API key, API key field, or category changes; force refresh when credentials or endpoint change.

- [ ] **Step 4: Run focused widget and compile tests**

Run: `cd client && flutter test test/widgets/app_provider/provider_model_picker_field_test.dart`

Expected: PASS with no analyzer errors from the interface signature change.

---

### Task 3: Add current static Codex and Claude catalogs

**Files:**
- Create: `client/lib/services/cli/codex/provider/codex_model_catalog.dart`
- Modify: `client/lib/services/cli/claude/provider/claude_model_catalog.dart`
- Test: `client/test/services/provider/codex/codex_model_catalog_test.dart`
- Modify: `client/test/services/provider/claude/claude_model_catalog_test.dart`

**Interfaces:**
- Consumes: current official model IDs from the approved design.
- Produces: `CodexModelCatalog.knownModelsForProvider`, `ClaudeModelCatalog.officialModels` including current IDs.

- [ ] **Step 1: Add failing assertions for current fallback IDs**

Assert that the Codex official catalog contains `gpt-5.6`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`, and `gpt-5.3-codex`. Assert that Claude contains `fable`, `claude-fable-5`, `claude-opus-4-8`, `claude-sonnet-5`, and `claude-haiku-4-5-20251001`. Keep existing assertions for legacy IDs.

- [ ] **Step 2: Run catalog tests and verify the new assertions fail**

Run: `cd client && flutter test test/services/provider/codex/codex_model_catalog_test.dart test/services/provider/claude/claude_model_catalog_test.dart`

Expected: FAIL because the new IDs are absent and Codex has no catalog class.

- [ ] **Step 3: Implement the static catalog sources**

Make Codex return static IDs only for `openai-official` or an official Codex provider. Make Claude add `fable` and the current generally released IDs while retaining aliases and existing models. Do not add invitation-only `claude-mythos-5` to the default fallback.

- [ ] **Step 4: Run catalog tests and verify green**

Run: `cd client && flutter test test/services/provider/codex/codex_model_catalog_test.dart test/services/provider/claude/claude_model_catalog_test.dart`

Expected: PASS.

---

### Task 4: Integrate live services into Codex and Claude capabilities

**Files:**
- Modify: `client/lib/services/cli/codex/capabilities/provider.dart`
- Modify: `client/lib/services/cli/claude/capabilities/provider.dart`
- Modify: `client/lib/services/cli/codex/codex_bootstrap_entry.dart`
- Modify: `client/lib/services/cli/claude/claude_bootstrap_entry.dart`
- Modify: `client/lib/services/cli/registry/built_in_cli_tools.dart`
- Modify: `client/lib/app/app_shell.dart`
- Create or modify: `client/test/services/provider/codex/codex_provider_model_capability_test.dart`
- Create or modify: `client/test/services/provider/claude/claude_provider_model_capability_test.dart`

**Interfaces:**
- Consumes: `ApiModelCatalogService`, static `CodexModelCatalog`, existing `ClaudeModelCatalog`.
- Produces: refreshable Codex and Claude capabilities with live-first/fallback model candidates.

- [ ] **Step 1: Add failing capability tests**

Cover these exact behaviors:

```dart
test('Codex live API ids take precedence for an API-key provider', () async {
  final capability = CodexProviderCapability(modelsService: modelsService);
  expect(capability.modelCandidates(provider: apiProvider), contains('live-codex'));
});

test('Codex OAuth provider uses static catalog without a network request', () async {
  final capability = CodexProviderCapability(modelsService: modelsService);
  expect(capability.modelCandidates(provider: oauthProvider), contains('gpt-5.3-codex'));
  expect(requestCount, 0);
});

test('Claude live API ids take precedence for an API-key provider', () async {
  final capability = ClaudeProviderCapability(modelsService: modelsService);
  expect(capability.modelCandidates(provider: apiProvider), contains('live-claude'));
});

test('Claude OAuth provider uses aliases and current static ids', () async {
  final capability = ClaudeProviderCapability(modelsService: modelsService);
  final candidates = capability.modelCandidates(provider: oauthProvider);
  expect(candidates, contains('sonnet'));
  expect(candidates, contains('claude-sonnet-4-6'));
});

test('Codex and Claude capabilities are refreshable', () {
  expect(CodexProviderCapability(modelsService: modelsService), isA<RefreshableProviderModelCapability>());
  expect(ClaudeProviderCapability(modelsService: modelsService), isA<RefreshableProviderModelCapability>());
});
```

- [ ] **Step 2: Run capability tests and verify they fail**

Run: `cd client && flutter test test/services/provider/codex/codex_provider_model_capability_test.dart test/services/provider/claude/claude_provider_model_capability_test.dart`

Expected: FAIL because the capabilities currently expose empty live/static sources and their bootstrap entries do not accept model services.

- [ ] **Step 3: Inject services through bootstrap and registry wiring**

Add nullable `modelsService` fields to `CodexBootstrapEntry` and `ClaudeBootstrapEntry`. Instantiate two `ApiModelCatalogService` objects in `app_shell.dart` with the application filesystem/base path and protocols/cache directories. Pass them from `built_in_cli_tools.dart` into the corresponding capabilities.

- [ ] **Step 4: Implement live-first catalog sources and refresh methods**

For both CLIs:

- return service IDs when the provider has a non-empty API key and live IDs are loaded;
- otherwise return the official static catalog only for official providers;
- keep custom providers' declared/default/current IDs through `CatalogModelCapability`;
- expose the service's `catalogUpdates`;
- implement `refreshModelCatalog` by forwarding provider ID, provider record, and `forceRefresh`;
- preserve existing picker mode, default model, credential behavior, and effort behavior.

- [ ] **Step 5: Run capability tests and verify green**

Run: `cd client && flutter test test/services/provider/codex/codex_provider_model_capability_test.dart test/services/provider/claude/claude_provider_model_capability_test.dart`

Expected: PASS.

---

### Task 5: Run repository verification and review the focused diff

**Files:**
- Modify only files from Tasks 1–4 if fixes are required.

- [ ] **Step 1: Run all focused model/provider tests**

Run:

```bash
cd client
flutter test \
  test/services/provider/api_model_catalog_service_test.dart \
  test/services/provider/codex/codex_model_catalog_test.dart \
  test/services/provider/claude/claude_model_catalog_test.dart \
  test/services/provider/codex/codex_provider_model_capability_test.dart \
  test/services/provider/claude/claude_provider_model_capability_test.dart \
  test/services/cli/opencode/provider/opencode_provider_model_capability_test.dart \
  test/services/provider/cursor/cursor_agent_models_service_test.dart
```

Expected: all focused tests PASS.

- [ ] **Step 2: Run the required analyzer**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: exit code 0.

- [ ] **Step 3: Run the required non-integration test suite**

Run: `cd client && flutter test --exclude-tags integration`

Expected: exit code 0 with zero failed tests.

- [ ] **Step 4: Inspect the diff and check for credential leakage**

Run:

```bash
git diff --check
git diff -- client/lib/services/provider/api_model_catalog_service.dart client/lib/services/cli/codex client/lib/services/cli/claude client/lib/services/cli/registry/capabilities/provider_capability.dart client/lib/widgets/app_provider/provider_model_picker_field.dart client/lib/app/app_shell.dart
rg -n "apiKey|Authorization|x-api-key" client/lib/services/provider/api_model_catalog_service.dart
```

Expected: no whitespace errors; API key usage appears only in request-header construction and no cache JSON contains credential fields.

- [ ] **Step 5: Request code review before claiming completion**

Use the requesting-code-review skill with the base commit immediately before the implementation and the implementation head commit. Fix all Critical/Important findings, rerun the full verification commands, and report any Minor findings separately.
