# Grok / Cursor / X 用量查询预设 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a built-in Managed Provider preset `grok-x` that queries grok.com dashboard usage-status and prepaid billing with the entry's Cursor CLI cookie, showing Weekly included-pool percent and dollar Prepaid.

**Architecture:** A new `GrokDashboardUsageAdapter` (`grok-dashboard-usage`) allowlists `grok.com`, sends the Cursor `WorkosCursorSessionToken` cookie, computes Weekly percent from `weeklyIncludedUsage.usedCents / budgetCents`, and maps Prepaid from `availableCents / 100` on a second POST. The preset does not use `http-json` windows. The existing Cursor preset is unchanged.

**Tech Stack:** Dart, Flutter, `ManagedProviderUsageAdapter`, `CliCredentialSourceResolver`, slang l10n, `dart run tool/run_tests.dart`.

## Global Constraints

- Never invoke `flutter test` directly. Always run `cd client && dart run tool/run_tests.dart <paths/options>` from the worktree.
- Before claiming done: `flutter analyze --no-fatal-infos --no-fatal-warnings` and `dart run tool/run_tests.dart`.
- Fast inner loop: targeted test files; full suite once at the end (Task 3).
- l10n: edit i18n JSON then `dart run slang`. Never hand-edit `translations_*.g.dart`.
- Never commit cookies, JWTs, or unredacted bodies. Errors must not include Cookie or token values. No `print`.
- Do not modify the existing `cursor` preset. Do not change `http-json` generic behavior.
- Do not send `WorkosCursorXaiOrigin`, grok SSO, or `cf_clearance`. Do not call `query-billing-items` or `query-daily-usage`.
- Adapter may only contact `https://grok.com` at `/dashboard/api/dashboard/v2/usage-status` (GET, `scope=user`) and `/dashboard/api/dashboard/get-user-prepaid-billing` (POST `{}`).
- Prepaid request failures omit Prepaid; they must not fail Weekly.
- Do not modify unrelated files. Stage explicit paths; never `git add -A`.
- No new dependencies.
- Work from `/home/hhoa/git/hhoa/teampilot/.worktrees/grok-x-usage-preset`.

## File Structure

- `client/lib/services/provider_usage/adapters/grok_dashboard_usage_adapter.dart` (new)
- `client/test/services/provider_usage/grok_dashboard_usage_adapter_test.dart` (new)
- `client/lib/services/provider_usage/managed_provider_presets.dart` (insert `grok-x` after `cursor`)
- `client/lib/app/app_shell.dart` (register adapter)
- `client/lib/widgets/managed_provider/managed_provider_brand_icon.dart` (Task 2)
- `client/lib/l10n/l10n_extensions.dart` + i18n JSON + slang (Task 3)
- Tests: `managed_provider_presets_test.dart`, `app_shell_provider_usage_bootstrap_test.dart`, `managed_provider_brand_icon_test.dart`

---

### Task 1: Adapter, registry, and grok-x preset

**Files:**
- Create: `client/lib/services/provider_usage/adapters/grok_dashboard_usage_adapter.dart`
- Create: `client/test/services/provider_usage/grok_dashboard_usage_adapter_test.dart`
- Modify: `client/lib/app/app_shell.dart` (`buildDefaultManagedProviderUsageRegistry`)
- Modify: `client/test/app/app_shell_provider_usage_bootstrap_test.dart`
- Modify: `client/lib/services/provider_usage/managed_provider_presets.dart`
- Modify: `client/test/services/provider_usage/managed_provider_presets_test.dart`

**Interfaces:**
- Consumes: `ManagedProviderUsageAdapter`, `CliCredentialSourceResolver`, `fillAccountIdFromJwt`, `throwOfficialHttpStatus`, `decodeOfficialJsonObject`, `formatOfficialPercent`, `parseOfficialResetAt`.
- Produces: `class GrokDashboardUsageAdapter implements ManagedProviderUsageAdapter` with `static const adapterId = 'grok-dashboard-usage'`; preset id `grok-x`.

- [ ] **Step 1: Write the failing adapter, registry, and preset tests**

Create `client/test/services/provider_usage/grok_dashboard_usage_adapter_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/services/provider_usage/adapters/grok_dashboard_usage_adapter.dart';
import 'package:teampilot/services/provider_usage/cli_credential_source.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';

void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true);

  ManagedProvider provider({
    String url =
        'https://grok.com/dashboard/api/dashboard/v2/usage-status?scope=user',
    String credentialSource = 'cli:cursor-mp-p1',
  }) => ManagedProvider(
    id: 'p1',
    name: 'Grok / Cursor / X',
    kind: ManagedProviderKind.subscriptionQuota,
    adapterId: GrokDashboardUsageAdapter.adapterId,
    endpointConfig: ManagedProviderEndpointConfig(
      url: url,
      method: 'GET',
      credentialSource: credentialSource,
    ),
  );

  GrokDashboardUsageAdapter adapter() => GrokDashboardUsageAdapter(
    cliCredentials: CliCredentialSourceResolver(
      readers: {
        'cursor': _CliReader(
          const _Scope({
            'accessToken': 'jwt-token',
            'accountId': 'user',
          }),
        ),
      },
    ),
  );

  Future<ProviderUsageSnapshot> fetch(_QueueHttp http, {String? url}) =>
      adapter().fetch(
        provider(url: url ?? provider().endpointConfig.url),
        credentials: const _Resolver(),
        http: http,
        now: now,
      );

  test('maps weekly percent and prepaid dollars', () async {
    final http = _QueueHttp([_usageOk, _prepaidOk]);
    final snapshot = await fetch(http);
    expect(http.requests, hasLength(2));
    expect(http.requests.first.method, 'GET');
    expect(
      http.requests.first.uri.toString(),
      'https://grok.com/dashboard/api/dashboard/v2/usage-status?scope=user',
    );
    expect(
      http.requests.first.headers['Cookie'],
      'WorkosCursorSessionToken=user::jwt-token',
    );
    expect(http.requests.first.headers['x-cursor-dashboard-surface'], 'v2');
    expect(http.requests.first.headers['Origin'], 'https://grok.com');
    expect(http.requests.last.method, 'POST');
    expect(
      http.requests.last.uri.toString(),
      'https://grok.com/dashboard/api/dashboard/get-user-prepaid-billing',
    );
    expect(jsonDecode(http.requests.last.body!), <String, Object?>{});
    expect(snapshot.measures.map((m) => m.label), ['Weekly', 'Prepaid']);
    expect(snapshot.measures.first.used, '42');
    expect(snapshot.measures.first.total, '100');
    expect(snapshot.measures.first.remaining, '58');
    expect(snapshot.measures.first.unit, '%');
    expect(
      snapshot.measures.first.resetsAt,
      DateTime.parse('2026-11-17T00:00:00.000Z').millisecondsSinceEpoch,
    );
    expect(snapshot.measures.last.remaining, '12.50');
    expect(snapshot.measures.last.unit, 'USD');
    expect(snapshot.measures.last.kind, ProviderUsageMeasureKind.balance);
  });

  test('omits prepaid when the prepaid request fails', () async {
    final snapshot = await fetch(
      _QueueHttp([
        _usageOk,
        const ProviderUsageHttpResponse(statusCode: 401, body: '{"error":"jwt-token"}'),
      ]),
    );
    expect(snapshot.measures.map((m) => m.label), ['Weekly']);
  });

  test('maps usage 401 to authenticationFailed without the token', () async {
    try {
      await fetch(
        _QueueHttp([
          const ProviderUsageHttpResponse(statusCode: 401, body: '{"error":"jwt-token"}'),
        ]),
      );
      fail('expected failure');
    } on ManagedProviderUsageQueryError catch (error) {
      expect(error.code, ManagedProviderUsageQueryErrorCode.authenticationFailed);
      expect(error.toString(), isNot(contains('jwt-token')));
    }
  });

  test('rejects a non-allowlisted URL without sending', () async {
    final http = _QueueHttp(const []);
    try {
      await fetch(http, url: 'https://evil.test/usage-status?scope=user');
      fail('expected failure');
    } on ManagedProviderUsageQueryError catch (error) {
      expect(error.code, ManagedProviderUsageQueryErrorCode.unsupported);
    }
    expect(http.requests, isEmpty);
  });

  test('throws responseParseFailed when weekly cannot be computed and prepaid is absent',
      () async {
    try {
      await fetch(
        _QueueHttp([
          const ProviderUsageHttpResponse(
            statusCode: 200,
            body: '{"availability":"available","weeklyIncludedUsage":{"usedCents":1,"budgetCents":0}}',
          ),
          const ProviderUsageHttpResponse(statusCode: 200, body: '{}'),
        ]),
      );
      fail('expected failure');
    } on ManagedProviderUsageQueryError catch (error) {
      expect(error.code, ManagedProviderUsageQueryErrorCode.responseParseFailed);
    }
  });
}

const _usageOk = ProviderUsageHttpResponse(
  statusCode: 200,
  body:
      '{"availability":"available","weeklyIncludedUsage":{"usedCents":4200,"budgetCents":10000,"resetsAt":"2026-11-17T00:00:00.000Z"}}',
);

const _prepaidOk = ProviderUsageHttpResponse(
  statusCode: 200,
  body:
      '{"billingMode":"PREPAID_BILLING_MODE_PREPAID","eligible":true,"availableCents":1250}',
);

class _Scope implements ProviderCredentialScope {
  const _Scope(this.values);
  final Map<String, String> values;
  @override
  bool get isEmpty => values.isEmpty;
  @override
  Iterable<String> get fields => values.keys;
  @override
  String? valueFor(String field) => values[field];
}

class _Resolver implements ProviderCredentialResolver {
  const _Resolver();
  @override
  Future<ProviderCredentialScope?> resolve(ManagedProvider provider) async =>
      null;
}

class _CliReader implements OfficialSubscriptionAuthReader {
  const _CliReader(this.scope);
  final ProviderCredentialScope scope;
  @override
  Future<ProviderCredentialScope?> read(ManagedProvider provider) async =>
      scope;
}

class _QueueHttp implements ProviderUsageHttpClient {
  _QueueHttp(this.responses);
  final List<ProviderUsageHttpResponse> responses;
  final requests = <ProviderUsageHttpRequest>[];
  @override
  Future<ProviderUsageHttpResponse> send(ProviderUsageHttpRequest request) async {
    requests.add(request);
    return responses[requests.length - 1];
  }
}
```

In `managed_provider_presets_test.dart`, insert `'grok-x'` immediately after `'cursor'` in both id lists. After the cursor expects add:

```dart
    final grokX = managedProviderPresetById('grok-x')!;
    expect(grokX.template.name, 'Grok / Cursor / X');
    expect(grokX.template.kind, ManagedProviderKind.subscriptionQuota);
    expect(grokX.template.adapterId, 'grok-dashboard-usage');
    expect(
      grokX.template.endpointConfig.url,
      'https://grok.com/dashboard/api/dashboard/v2/usage-status?scope=user',
    );
    expect(grokX.template.endpointConfig.credentialSource, 'cli:cursor');
    expect(grokX.template.endpointConfig.windows, isEmpty);
    expect(
      cursor.template.endpointConfig.url,
      'https://cursor.com/api/usage-summary',
    );
```

In `app_shell_provider_usage_bootstrap_test.dart`, change the default-registry test so `adapterFor('grok-dashboard-usage')` is `isA<GrokDashboardUsageAdapter>()` (import the adapter). Keep http-json. The test name may say it exposes http-json and grok-dashboard-usage.

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /home/hhoa/git/hhoa/teampilot/.worktrees/grok-x-usage-preset/client && \
  dart run tool/run_tests.dart \
    test/services/provider_usage/grok_dashboard_usage_adapter_test.dart \
    test/services/provider_usage/managed_provider_presets_test.dart \
    test/app/app_shell_provider_usage_bootstrap_test.dart
```

Expected: FAIL (missing adapter class and/or `grok-x` preset).

- [ ] **Step 3: Implement adapter, register it, add the preset**

Create `grok_dashboard_usage_adapter.dart`:

- `id` / `adapterId` = `grok-dashboard-usage`
- Constructor `{CliCredentialSourceResolver? cliCredentials}`
- Validate usage URL as in the spec
- Read CLI scope via `cliCredentials.read(provider.endpointConfig.credentialSource)`, then `fillAccountIdFromJwt`
- Cookie `WorkosCursorSessionToken={accountId}::{accessToken}`
- GET usage-status; map Weekly from `availability == available` and `usedCents/budgetCents`
- POST prepaid on same host; omit Prepaid on any failure
- Format percent with `formatOfficialPercent`; dollars from cents: integer dollars without decimals, otherwise two decimal places
- `throwOfficialHttpStatus` / `decodeOfficialJsonObject` for usage-status only

Register in `buildDefaultManagedProviderUsageRegistry`:

```dart
    HttpJsonMappingAdapter(cliCredentials: cliCredentials),
    GrokDashboardUsageAdapter(cliCredentials: cliCredentials),
```

Insert the `grok-x` preset immediately after `cursor` with `adapterId: 'grok-dashboard-usage'`, the grok.com usage-status URL, `credentialSource: 'cli:cursor'`, empty windows, no displayConfig.

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add \
  client/lib/services/provider_usage/adapters/grok_dashboard_usage_adapter.dart \
  client/test/services/provider_usage/grok_dashboard_usage_adapter_test.dart \
  client/lib/app/app_shell.dart \
  client/test/app/app_shell_provider_usage_bootstrap_test.dart \
  client/lib/services/provider_usage/managed_provider_presets.dart \
  client/test/services/provider_usage/managed_provider_presets_test.dart
git commit -m "$(cat <<'EOF'
feat(provider-usage): add Grok/Cursor/X dashboard usage adapter

Compute weekly percent from usedCents/budgetCents and prepaid dollars
from availableCents using the entry Cursor CLI cookie.
EOF
)"
```

---

### Task 2: grok.com brand icon

**Files:**
- Modify: `client/test/widgets/managed_provider/managed_provider_brand_icon_test.dart`
- Modify: `client/lib/widgets/managed_provider/managed_provider_brand_icon.dart`

**Interfaces:**
- Produces: host `grok.com` → `ManagedProviderBrandIconSpec.bundled('grok')`.

- [ ] **Step 1: Write the failing icon test**

After the Cursor host test:

```dart
  test('Grok host uses bundled grok', () {
    expect(
      resolveManagedProviderBrandIcon(
        _provider(
          name: 'Grok / Cursor / X',
          url:
              'https://grok.com/dashboard/api/dashboard/v2/usage-status?scope=user',
        ).copyWith(kind: ManagedProviderKind.subscriptionQuota),
      ),
      const ManagedProviderBrandIconSpec.bundled('grok'),
    );
  });
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd /home/hhoa/git/hhoa/teampilot/.worktrees/grok-x-usage-preset/client && \
  dart run tool/run_tests.dart \
    test/widgets/managed_provider/managed_provider_brand_icon_test.dart \
    --plain-name "Grok host uses bundled grok"
```

Expected: FAIL (initials icon).

- [ ] **Step 3: Map grok.com**

Immediately after the `cursor.com` branch:

```dart
  if (host == 'grok.com') {
    return const ManagedProviderBrandIconSpec.bundled('grok');
  }
```

- [ ] **Step 4: Run icon tests — Expected: PASS**

```bash
cd /home/hhoa/git/hhoa/teampilot/.worktrees/grok-x-usage-preset/client && \
  dart run tool/run_tests.dart \
    test/widgets/managed_provider/managed_provider_brand_icon_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add \
  client/lib/widgets/managed_provider/managed_provider_brand_icon.dart \
  client/test/widgets/managed_provider/managed_provider_brand_icon_test.dart
git commit -m "$(cat <<'EOF'
feat(provider-usage): use grok brand icon for grok.com usage preset
EOF
)"
```

---

### Task 3: Preset label and hint

**Files:**
- Modify: `client/lib/i18n/managedProviders_en.i18n.json`
- Modify: `client/lib/i18n/managedProviders_zh.i18n.json`
- Modify: `client/lib/l10n/l10n_extensions.dart`
- Generate: `client/lib/l10n/translations_en.g.dart`, `client/lib/l10n/translations_zh.g.dart`

**Interfaces:**
- Produces: id `grok-x` → `quickPresetGrokX` / `quickPresetGrokXHint`.

- [ ] **Step 1: Add i18n keys after `quickPresetCursorHint`**

EN:

```json
  "quickPresetGrokX": "Grok / Cursor / X",
  "quickPresetGrokXHint": "Query the unified weekly pool and prepaid balance on grok.com with your Cursor sign-in.",
```

ZH:

```json
  "quickPresetGrokX": "Grok / Cursor / X",
  "quickPresetGrokXHint": "使用 Cursor 登录态查询 grok.com 合一后的周额度和预付费。",
```

- [ ] **Step 2: Map id `grok-x` in `l10n_extensions.dart` immediately after the cursor arms**

```dart
    'grok-x' => managedProviders.quickPresetGrokX,
```

```dart
    'grok-x' => managedProviders.quickPresetGrokXHint,
```

- [ ] **Step 3: `cd client && dart run slang`** — Expected: exit 0.

- [ ] **Step 4: Analyze and targeted tests**

```bash
cd /home/hhoa/git/hhoa/teampilot/.worktrees/grok-x-usage-preset/client && \
  flutter analyze --no-fatal-infos --no-fatal-warnings && \
  dart run tool/run_tests.dart \
    test/services/provider_usage/grok_dashboard_usage_adapter_test.dart \
    test/services/provider_usage/managed_provider_presets_test.dart \
    test/app/app_shell_provider_usage_bootstrap_test.dart \
    test/widgets/managed_provider/managed_provider_brand_icon_test.dart
```

Expected: analyze clean; tests PASS.

- [ ] **Step 5: Commit**

```bash
git add \
  client/lib/i18n/managedProviders_en.i18n.json \
  client/lib/i18n/managedProviders_zh.i18n.json \
  client/lib/l10n/l10n_extensions.dart \
  client/lib/l10n/translations_en.g.dart \
  client/lib/l10n/translations_zh.g.dart
git commit -m "$(cat <<'EOF'
feat(l10n): label Grok/Cursor/X usage preset
EOF
)"
```

- [ ] **Step 6: Full suite once**

```bash
cd /home/hhoa/git/hhoa/teampilot/.worktrees/grok-x-usage-preset/client && \
  dart run tool/run_tests.dart
```

Expected: PASS. Do not claim done until this exits 0.

---

## Spec coverage

| Spec requirement | Task |
|------------------|------|
| Adapter computes weekly % from cents; prepaid from availableCents | Task 1 |
| Preset `grok-x` after Cursor, `cli:cursor`, grok.com URL | Task 1 |
| Registry registration | Task 1 |
| Prepaid failure does not fail Weekly | Task 1 |
| Host allowlist | Task 1 |
| grok.com icon | Task 2 |
| EN/ZH label and hint | Task 3 |
