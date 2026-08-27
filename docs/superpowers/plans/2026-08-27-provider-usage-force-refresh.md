# Provider Usage Force Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh every enabled provider directly on auto-refresh start, timer ticks, and app resume without consulting cache expiration.

**Architecture:** Add a cubit operation that reloads the catalog and calls the existing forced `refreshAll` path. Have the auto-refresh service call that operation immediately at startup and on each ten-minute tick; replace the app-resume call with the same operation. Existing coordinator single-flight handling prevents overlapping transport work.

**Tech Stack:** Dart, Flutter, `flutter_test`.

## Global Constraints

- Keep persisted snapshots and their existing schema unchanged.
- Do not use `staleAt` to suppress automatic requests.
- Refresh only enabled Providers; retain manual refresh behavior.

---

### Task 1: Force refresh from automatic triggers

**Files:**
- Modify: `client/test/cubits/managed_provider_usage_cubit_test.dart:350-376`
- Modify: `client/test/services/provider_usage/managed_provider_usage_auto_refresh_test.dart:121-153`
- Modify: `client/lib/cubits/managed_provider_usage_cubit.dart:264-274`
- Modify: `client/lib/services/provider_usage/managed_provider_usage_auto_refresh.dart:42-65`
- Modify: `client/lib/app/app_shell.dart:2557-2563`

**Interfaces:**
- Produces: `ManagedProviderUsageCubit.refreshEnabled()` returning `Future<List<ProviderUsageSnapshot>>`, which reloads provider state then forces a refresh for every enabled Provider.
- Consumes: `ManagedProviderUsageAutoRefresh` invokes `refreshEnabled()` when started and on timer ticks.

- [ ] **Step 1: Write failing cubit tests**

Replace the fresh-cache expectation with a test that stores `_ready(staleAt: 1_000)` while `now` is `100`, calls `refreshEnabled()`, and asserts `adapter.calls == 1`. Keep the disabled Provider fixture and assert it is not queried.

- [ ] **Step 2: Write failing auto-refresh start test**

Configure an enabled provider with a fresh `_ready()` snapshot, start `ManagedProviderUsageAutoRefresh`, wait for one event turn, and assert `adapter.calls == 1`. Fire the captured periodic callback and assert `adapter.calls == 2`.

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd client && flutter test test/cubits/managed_provider_usage_cubit_test.dart test/services/provider_usage/managed_provider_usage_auto_refresh_test.dart`

Expected: FAIL because fresh snapshots are skipped and `start()` does not trigger a query.

- [ ] **Step 4: Implement the minimal force-refresh operation**

Replace `refreshExpiredEnabled()` with:

```dart
Future<List<ProviderUsageSnapshot>> refreshEnabled() async {
  await load();
  if (isClosed) return const [];
  return refreshAll();
}
```

Update automatic callers to call `refreshEnabled()`. In `start()`, invoke the same refresh after creating the timer:

```dart
unawaited(_usage.refreshEnabled());
```

- [ ] **Step 5: Run focused tests and analysis**

Run: `cd client && flutter test test/cubits/managed_provider_usage_cubit_test.dart test/services/provider_usage/managed_provider_usage_auto_refresh_test.dart test/services/provider_usage/http_json_mapping_adapter_test.dart && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: tests pass; analysis exits successfully with any pre-existing warnings permitted by the command flags.

- [ ] **Step 6: Commit**

```bash
git add client/lib/cubits/managed_provider_usage_cubit.dart \
  client/lib/services/provider_usage/managed_provider_usage_auto_refresh.dart \
  client/lib/app/app_shell.dart \
  client/test/cubits/managed_provider_usage_cubit_test.dart \
  client/test/services/provider_usage/managed_provider_usage_auto_refresh_test.dart
git commit -m "fix: force refresh enabled provider usage"
```
