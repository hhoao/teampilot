# API Balance Auto Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make enabled HTTP/JSON API-balance providers refresh automatically once their cached snapshot reaches ten minutes old.

**Architecture:** `HttpJsonMappingConfig` will give HTTP/JSON responses a default ten-minute cache lifetime. The existing adapter converts that duration to `ProviderUsageSnapshot.staleAt`; the existing auto-refresh timer then detects the expired snapshot and fetches it. No new timer, configuration field, or UI is needed.

**Tech Stack:** Dart, Flutter, `flutter_test`.

## Global Constraints

- Preserve the existing ten-minute periodic timer and manual forced-refresh behavior.
- Do not change managed-provider JSON schema or add UI configuration.
- Keep the change scoped to `http-json` provider usage snapshots.

---

### Task 1: Expire HTTP/JSON API-balance cache entries

**Files:**
- Modify: `client/test/services/provider_usage/http_json_mapping_adapter_test.dart`
- Modify: `client/lib/services/provider_usage/adapters/http_json_mapping_adapter.dart:47-72`

**Interfaces:**
- Consumes: `HttpJsonMappingAdapter.fetch(ManagedProvider, {credentials, http, now})`.
- Produces: a `ProviderUsageSnapshot` with `staleAt == now + const Duration(minutes: 10)` when the adapter fetch succeeds.

- [ ] **Step 1: Write the failing test**

Add a test beside the existing successful HTTP/JSON mapping tests. Create the adapter with its normal test HTTP client, fetch the test provider at a fixed time, and assert the returned snapshot expires ten minutes later:

```dart
test('marks a successful HTTP/JSON snapshot stale after ten minutes', () async {
  final snapshot = await adapter.fetch(
    provider,
    credentials: credentials,
    http: http,
    now: DateTime.fromMillisecondsSinceEpoch(1_000),
  );

  expect(snapshot.staleAt, 601_000);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/provider_usage/http_json_mapping_adapter_test.dart --plain-name "marks a successful HTTP/JSON snapshot stale after ten minutes"`

Expected: FAIL because `snapshot.staleAt` is `null`.

- [ ] **Step 3: Write minimal implementation**

Give `HttpJsonMappingConfig.staleAfter` a default of ten minutes so the existing snapshot construction persists the expiry:

```dart
this.staleAfter = const Duration(minutes: 10),
```

Keep the existing `staleAt` calculation unchanged:

```dart
staleAt: mapping.staleAfter == null
    ? null
    : now.add(mapping.staleAfter!).millisecondsSinceEpoch,
```

- [ ] **Step 4: Run focused tests to verify they pass**

Run: `cd client && flutter test test/services/provider_usage/http_json_mapping_adapter_test.dart test/cubits/managed_provider_usage_cubit_test.dart test/services/provider_usage/managed_provider_usage_auto_refresh_test.dart`

Expected: PASS with no failing tests.

- [ ] **Step 5: Run static analysis and commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: exit code 0.

Commit only the implementation and its test:

```bash
git add client/lib/services/provider_usage/adapters/http_json_mapping_adapter.dart \
  client/test/services/provider_usage/http_json_mapping_adapter_test.dart
git commit -m "fix: auto refresh API balance providers"
```
