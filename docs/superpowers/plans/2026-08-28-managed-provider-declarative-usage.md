# Managed Provider Declarative Usage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** All managed-provider usage queries go through `http-json`; Codex / Claude / Cursor presets only pre-fill that config.

**Architecture:** Extend `ManagedProviderEndpointConfig` with `credentialSource`, `credentialTemplate`, and `windows`. `HttpJsonMappingAdapter` expands header/credential templates and maps named windows. CLI tokens are read by `CliCredentialSourceResolver` (existing file readers) when `credentialSource` is `cli:<id>`. Delete official subscription adapters. No migration of old `official-*-subscription` rows.

**Tech Stack:** Flutter/Dart, existing `HttpJsonMappingAdapter`, `ProviderUsageHttpClient`, CLI auth file readers.

**Spec:** `docs/superpowers/specs/2026-08-28-managed-provider-declarative-usage-design.md`

## Global Constraints

- Official CLI tokens never enter Managed Provider JSON or SecretStore.
- Query-time CLI auth must not scan all `AppProviderConfig` rows.
- l10n only in `app_en.arb` / `app_zh.arb`.
- TDD: failing test first, then minimal code.
- Do not commit unless the user asks. Skip every Commit step until then.

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/models/managed_provider.dart` | `credentialSource`, `credentialTemplate`, `windows` on endpoint config |
| `client/lib/services/provider_usage/http_json_template.dart` | Placeholder expansion + JWT `sub` |
| `client/lib/services/provider_usage/cli_credential_source.dart` | `cli:<id>` → existing auth readers |
| `client/lib/services/provider_usage/adapters/http_json_mapping_adapter.dart` | Request templates + windows mapping |
| `client/lib/services/provider_usage/managed_provider_presets.dart` | Codex/Claude/Cursor as filled `http-json` |
| `client/lib/services/provider_usage/official_managed_provider_binding.dart` | Lookup by `cli:<id>` not adapter id |
| `client/lib/pages/managed_providers/managed_provider_official_credentials.dart` | Login bar keyed by credential source |
| `client/lib/widgets/managed_provider/managed_provider_brand_icon.dart` | Icon from URL host / name |
| `client/lib/app/app_shell.dart` | Registry is `http-json` + CLI resolver only |
| Delete | `*_subscription_adapter.dart`, `*_official_subscription_client.dart` |

Keep `*_official_subscription_auth.dart` (file readers). Delete `official_subscription_adapter.dart` only after moving `OfficialSubscriptionAuthReader` into `cli_credential_source.dart` (or keep that one file as the auth interface).

---

### Task 1: Endpoint config fields

**Files:**
- Modify: `client/lib/models/managed_provider.dart`
- Test: `client/test/models/managed_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `client/test/models/managed_provider_test.dart`:

```dart
test('round-trips credential source template and windows', () {
  final provider = ManagedProvider(
    id: 'p1',
    name: 'Cursor',
    kind: ManagedProviderKind.subscriptionQuota,
    adapterId: 'http-json',
    endpointConfig: ManagedProviderEndpointConfig(
      url: 'https://cursor.com/api/usage-summary',
      credentialSource: 'cli:cursor-account',
      credentialName: 'Cookie',
      credentialTemplate: 'WorkosCursorSessionToken={accountId}::{accessToken}',
      headers: {'Accept': 'application/json'},
      windows: const [
        ManagedProviderUsageWindow(
          label: 'Plan',
          used: r'$.individualUsage.plan.totalPercentUsed',
          unit: '%',
          resetsAt: r'$.billingCycleEnd',
        ),
      ],
    ),
  );

  expect(ManagedProvider.fromJson(provider.toJson()), provider);
  expect(
    (provider.toJson()['endpointConfig'] as Map)['credentialSource'],
    'cli:cursor-account',
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/managed_provider_test.dart --name "credential source"`

Expected: FAIL — `ManagedProviderUsageWindow` / `credentialSource` not defined.

- [ ] **Step 3: Write minimal implementation**

In `managed_provider.dart`, add:

```dart
@immutable
class ManagedProviderUsageWindow extends Equatable {
  const ManagedProviderUsageWindow({
    required this.label,
    this.used,
    this.total,
    this.remaining,
    this.resetsAt,
    this.unit,
    this.kind,
  });

  factory ManagedProviderUsageWindow.fromJson(Map<String, Object?> json) =>
      ManagedProviderUsageWindow(
        label: json['label'] as String? ?? '',
        used: json['used'] as String?,
        total: json['total'] as String?,
        remaining: json['remaining'] as String?,
        resetsAt: json['resetsAt'] as String?,
        unit: json['unit'] as String?,
        kind: json['kind'] as String?,
      );

  final String label;
  final String? used;
  final String? total;
  final String? remaining;
  final String? resetsAt;
  final String? unit;
  final String? kind;

  Map<String, Object?> toJson() => {
    'label': label,
    if (used != null) 'used': used,
    if (total != null) 'total': total,
    if (remaining != null) 'remaining': remaining,
    if (resetsAt != null) 'resetsAt': resetsAt,
    if (unit != null) 'unit': unit,
    if (kind != null) 'kind': kind,
  };

  @override
  List<Object?> get props => [label, used, total, remaining, resetsAt, unit, kind];
}
```

Extend `ManagedProviderEndpointConfig` factory + fields + `fromJson` / `toJson` / `props` with:

- `credentialSource` default `'secret'`
- `credentialTemplate` optional
- `windows` default `const []`

Parse `windows` as a list of maps; omit empty `windows` and default `credentialSource` from JSON output when they are the defaults (`secret` / empty list) so DeepSeek JSON stays small.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/models/managed_provider_test.dart`

Expected: PASS

---

### Task 2: Template expansion

**Files:**
- Create: `client/lib/services/provider_usage/http_json_template.dart`
- Test: `client/test/services/provider_usage/http_json_template_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider_usage/http_json_template.dart';

void main() {
  test('empty accountId drops colon separators', () {
    expect(
      expandHttpJsonTemplate(
        '{accountId}::{accessToken}',
        {'accessToken': 'tok'},
      ),
      'tok',
    );
  });

  test('jwt.sub uses the segment after the last pipe', () {
    final payload = base64Url
        .encode(utf8.encode('{"sub":"github|user_01ABC"}'))
        .replaceAll('=', '');
    final jwt = 'eyJhbGciOiJub25lIn0.$payload.sig';
    expect(
      expandHttpJsonTemplate('{jwt.sub}', {'accessToken': jwt}),
      'user_01ABC',
    );
  });

  test('fillAccountIdFromJwt writes accountId when missing', () {
    final payload = base64Url
        .encode(utf8.encode('{"sub":"user_01ABC"}'))
        .replaceAll('=', '');
    final jwt = 'eyJhbGciOiJub25lIn0.$payload.sig';
    final filled = fillAccountIdFromJwt({'accessToken': jwt});
    expect(filled['accountId'], 'user_01ABC');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/provider_usage/http_json_template_test.dart`

Expected: FAIL — library missing.

- [ ] **Step 3: Write minimal implementation**

`http_json_template.dart`:

- Replace `{name}` from the values map; unknown names → empty.
- `{jwt.sub}`: decode `accessToken` JWT payload `sub`; if `sub` contains `|`, take the substring after the last `|`.
- After substitution, strip leading/trailing `:`, collapse runs of `:` to a single `:`.
- `fillAccountIdFromJwt`: if `accountId` is missing/empty and jwt sub parses, return a copy with `accountId` set.

Empty expansion result is a valid empty string (the adapter turns that into `missingCredential` later).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/provider_usage/http_json_template_test.dart`

Expected: PASS

---

### Task 3: Windows mapping in http-json

**Files:**
- Modify: `client/lib/services/provider_usage/adapters/http_json_mapping_adapter.dart`
- Test: `client/test/services/provider_usage/http_json_mapping_adapter_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('maps named windows and skips paths that have no numbers', () async {
  final adapter = HttpJsonMappingAdapter();
  final provider = ManagedProvider(
    id: 'p1',
    name: 'Cursor',
    kind: ManagedProviderKind.subscriptionQuota,
    adapterId: 'http-json',
    endpointConfig: ManagedProviderEndpointConfig(
      url: 'https://cursor.com/api/usage-summary',
      windows: const [
        ManagedProviderUsageWindow(
          label: 'Plan',
          used: r'$.individualUsage.plan.totalPercentUsed',
          unit: '%',
          resetsAt: r'$.billingCycleEnd',
        ),
        ManagedProviderUsageWindow(
          label: 'Team',
          used: r'$.teamUsage.pooled.used',
          total: r'$.teamUsage.pooled.limit',
        ),
      ],
    ),
  );
  final snapshot = await adapter.fetch(
    provider,
    credentials: const _Resolver(null),
    http: FakeProviderUsageHttpClient(
      response: const ProviderUsageHttpResponse(
        statusCode: 200,
        body:
            '{"billingCycleEnd":"2026-04-01T00:00:00Z","individualUsage":{"plan":{"totalPercentUsed":30}}}',
      ),
    ),
    now: now,
  );
  expect(snapshot.measures, hasLength(1));
  expect(snapshot.measures.single.label, 'Plan');
  expect(snapshot.measures.single.used, '30');
  expect(snapshot.measures.single.total, '100');
  expect(snapshot.measures.single.unit, '%');
});
```

Also add: all windows missing numbers → `responseParseFailed`.

`HttpJsonMappingConfig.fromProvider` must copy `windows` from the endpoint.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/provider_usage/http_json_mapping_adapter_test.dart --name "named windows"`

Expected: FAIL — still uses measuresPath / ignores windows.

- [ ] **Step 3: Write minimal implementation**

When `mapping.windows` is not empty:

- Decode JSON object as today.
- For each window, `_lookupPath` used/total/remaining/resetsAt.
- Skip if all three numeric fields are null.
- If `unit` is `%` and only `used` is present, set total `100` and remaining `100-used` (reuse existing decimal formatting; clamp 0–100).
- If the resulting list is empty, throw `responseParseFailed`.

If `windows` is empty, keep the current `measuresPath` behavior (DeepSeek).

No credential required for this test (`credential` null).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/provider_usage/http_json_mapping_adapter_test.dart`

Expected: PASS (existing tests still pass)

---

### Task 4: CLI credential source

**Files:**
- Create: `client/lib/services/provider_usage/cli_credential_source.dart`
- Test: `client/test/services/provider_usage/cli_credential_source_test.dart`
- Move interface: `OfficialSubscriptionAuthReader` from `official_subscription_adapter.dart` into `cli_credential_source.dart` (or keep importing it until Task 9)

- [ ] **Step 1: Write the failing test**

Reuse `InMemoryFilesystem` like `official_subscription_auth_test.dart`.

```dart
test('cli:cursor-account prefers isolated auth.json', () async {
  final fs = InMemoryFilesystem();
  final layout = CursorHomeLayout(pathContext: fs.pathContext);
  await fs.writeString(
    layout.authJson('/tp/providers/cursor/cursor-account/home'),
    jsonEncode({'accessToken': 'isolated-cursor'}),
  );
  await fs.writeString(
    layout.cliConfig('/tp/providers/cursor/cursor-account/home'),
    jsonEncode({'authInfo': {'userId': 'user_isolated'}}),
  );
  final scope = await CliCredentialSourceResolver(
    readers: {
      'cursor-account': CursorOfficialSubscriptionAuthReader(
        fs: fs,
        basePath: '/tp',
        homeDirectory: () => '/home',
      ),
    },
  ).read('cli:cursor-account');
  expect(scope.valueFor('accessToken'), 'isolated-cursor');
  expect(scope.valueFor('accountId'), 'user_isolated');
});

test('unknown cli source is missingCredential', () async {
  await expectLater(
    CliCredentialSourceResolver(readers: {}).read('cli:nope'),
    throwsA(isA<ManagedProviderUsageQueryError>().having(
      (e) => e.code,
      'code',
      ManagedProviderUsageQueryErrorCode.missingCredential,
    )),
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/provider_usage/cli_credential_source_test.dart`

Expected: FAIL — type missing.

- [ ] **Step 3: Write minimal implementation**

```dart
class CliCredentialSourceResolver {
  const CliCredentialSourceResolver({required this.readers});
  final Map<String, OfficialSubscriptionAuthReader> readers;

  Future<ProviderCredentialScope> read(String source) async {
    const prefix = 'cli:';
    if (!source.startsWith(prefix)) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
    final id = source.substring(prefix.length);
    final reader = readers[id];
    if (reader == null) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
    final dummy = ManagedProvider(
      id: id,
      name: id,
      kind: ManagedProviderKind.subscriptionQuota,
      adapterId: 'http-json',
    );
    final scope = await reader.read(dummy);
    if (scope == null || scope.isEmpty) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
    return scope;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/provider_usage/cli_credential_source_test.dart test/services/provider_usage/official_subscription_auth_test.dart`

Expected: PASS

---

### Task 5: Request templates + CLI source in http-json

**Files:**
- Modify: `client/lib/services/provider_usage/adapters/http_json_mapping_adapter.dart`
- Test: `client/test/services/provider_usage/http_json_mapping_adapter_test.dart`

- [ ] **Step 1: Write the failing tests**

1. Header `ChatGPT-Account-Id: {accountId}` omitted when accountId missing; `Authorization` uses Bearer token from secret scope `accessToken`.
2. Cookie template `WorkosCursorSessionToken={accountId}::{accessToken}` with CLI resolver.
3. Custom provider with the same endpoint fields as (2) produces the same Cookie header (proves presets are not special-cased).

```dart
test('omits templated headers whose value expands empty', () async {
  final http = FakeProviderUsageHttpClient(
    response: const ProviderUsageHttpResponse(
      statusCode: 200,
      body: '{"remaining":"1"}',
    ),
  );
  await HttpJsonMappingAdapter().fetch(
    ManagedProvider(
      id: 'p1',
      name: 'Codex',
      kind: ManagedProviderKind.subscriptionQuota,
      adapterId: 'http-json',
      endpointConfig: ManagedProviderEndpointConfig(
        url: 'https://chatgpt.com/backend-api/wham/usage',
        credentialField: 'accessToken',
        credentialName: 'Authorization',
        credentialPrefix: 'Bearer ',
        headers: {'ChatGPT-Account-Id': '{accountId}', 'Accept': 'application/json'},
      ),
    ),
    credentials: const _Resolver(_Credentials({'accessToken': 'tok'})),
    http: http,
    now: now,
  );
  expect(http.requests.single.headers['Authorization'], 'Bearer tok');
  expect(http.requests.single.headers.containsKey('ChatGPT-Account-Id'), isFalse);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/provider_usage/http_json_mapping_adapter_test.dart --name "omits templated"`

Expected: FAIL — header sent as literal `{accountId}` or as empty string still present.

- [ ] **Step 3: Write minimal implementation**

In `_buildRequest`:

1. Resolve scope: if `credentialSource` starts with `cli:`, call injected `CliCredentialSourceResolver`; else existing secret resolver (only if credential field/name/template is set).
2. Convert scope to a `Map<String, String>`, then `fillAccountIdFromJwt`.
3. Expand each header value; skip keys whose expansion is empty.
4. Credential value: `credentialTemplate` if set, else `prefix + valueFor(field)`. Expand template. Empty → `missingCredential`.
5. Inject `HttpJsonMappingAdapter({this.cliCredentials})`. Tests that do not use `cli:` leave it null; using `cli:` without a resolver → `missingCredential`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/provider_usage/http_json_mapping_adapter_test.dart`

Expected: PASS

---

### Task 6: Presets become filled http-json templates

**Files:**
- Modify: `client/lib/services/provider_usage/managed_provider_presets.dart`
- Modify: `client/lib/l10n/l10n_extensions.dart` (hints already exist)
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb` — hints: 登录或导入，或手填相同字段
- Test: `client/test/services/provider_usage/managed_provider_presets_test.dart`
- Test: `client/test/services/provider_usage/http_json_mapping_adapter_test.dart` (preset fetch)

- [ ] **Step 1: Write the failing test**

```dart
test('built-in presets expose stable provider templates', () {
  expect(builtInManagedProviderPresets.map((preset) => preset.id), [
    'codex',
    'claude-code',
    'cursor',
    'deepseek',
  ]);
  final cursor = managedProviderPresetById('cursor')!;
  expect(cursor.template.adapterId, 'http-json');
  expect(cursor.template.kind, ManagedProviderKind.subscriptionQuota);
  expect(cursor.template.endpointConfig.url, 'https://cursor.com/api/usage-summary');
  expect(cursor.template.endpointConfig.credentialSource, 'cli:cursor-account');
  expect(
    cursor.template.endpointConfig.credentialTemplate,
    'WorkosCursorSessionToken={accountId}::{accessToken}',
  );
});
```

Add a fetch test: `HttpJsonMappingAdapter` + Cursor preset template + fixture body from the spec produces Plan/Auto/API windows. Repeat Claude (`five_hour`/`seven_day`) and Codex (primary/secondary/monthly).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/provider_usage/managed_provider_presets_test.dart`

Expected: FAIL — Codex/Claude still `official-*-subscription`; Cursor may already exist from earlier work but adapterId is official.

- [ ] **Step 3: Write minimal implementation**

Set all four presets `adapterId: 'http-json'`. DeepSeek unchanged (`credentialSource` default `secret`).

Fill Codex / Claude / Cursor `endpointConfig` exactly as the spec (URL, headers, credential fields, windows list). Give each a `ManagedProviderEditorSchema` built from the template (or rely on `fromProvider` at edit time). Query section will appear because adapter is `http-json`.

Run `flutter gen-l10n` after arb hint edits.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/provider_usage/managed_provider_presets_test.dart test/services/provider_usage/http_json_mapping_adapter_test.dart`

Expected: PASS

---

### Task 7: Login bar keyed by credentialSource

**Files:**
- Modify: `client/lib/services/provider_usage/official_managed_provider_binding.dart`
- Modify: `client/lib/pages/managed_providers/managed_provider_official_credentials.dart`
- Modify: `client/lib/pages/managed_providers/managed_provider_editor_page.dart`
- Test: `client/test/services/provider_usage/official_managed_provider_binding_test.dart`
- Test: `client/test/pages/managed_providers/managed_provider_management_page_test.dart`

- [ ] **Step 1: Write the failing test**

Replace adapter-id mapping tests:

```dart
test('maps cli credential sources to CLI provider rows', () {
  final cursor = OfficialManagedProviderBinding.forCredentialSource(
    'cli:cursor-account',
  );
  expect(cursor?.cli, CliTool.cursor);
  expect(cursor?.appProviderId, 'cursor-account');
  expect(OfficialManagedProviderBinding.forCredentialSource('secret'), isNull);
});
```

Widget test: apply Cursor preset → `managed-provider-official-credentials` and `Sign in with Cursor`. DeepSeek still shows API key, no login bar.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/provider_usage/official_managed_provider_binding_test.dart test/pages/managed_providers/managed_provider_management_page_test.dart --name "Cursor preset"`

Expected: FAIL — `forAdapter` still used; editor keys off adapter id.

- [ ] **Step 3: Write minimal implementation**

```dart
static OfficialManagedProviderBinding? forCredentialSource(String source) {
  switch (source.trim()) {
    case 'cli:openai-official': // CodexProviderPresets.byId('openai-official')
    case 'cli:claude-official':
    case 'cli:cursor-account':
    default: return null;
  }
}
```

Delete `forAdapter`.

Editor:

```dart
bool get _isCliCredentialSource =>
    OfficialManagedProviderBinding.forCredentialSource(
      _endpointCredentialSource,
    ) != null;
```

`ManagedProviderOfficialCredentials` takes `credentialSource` instead of `adapterId`. Codex preset test that looks for `Sign in with OpenAI` still passes if credential source is `cli:openai-official`.

Remove `_isOfficialSubscriptionAdapter` from `managed_provider_editor_schema.dart` (kind readOnly stays `kind != customHttp`).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/provider_usage/official_managed_provider_binding_test.dart test/pages/managed_providers/managed_provider_management_page_test.dart test/models/managed_provider_editor_schema_test.dart`

Expected: PASS. Update schema tests that assumed official adapters hide query — they must now expect query fields for http-json Codex/Cursor templates.

---

### Task 8: Brand icons from host / name

**Files:**
- Modify: `client/lib/widgets/managed_provider/managed_provider_brand_icon.dart`
- Test: `client/test/widgets/managed_provider/managed_provider_brand_icon_test.dart`

- [ ] **Step 1: Write the failing test**

Replace adapter-id cases:

```dart
test('Cursor usage URL uses bundled cursor', () {
  expect(
    resolveManagedProviderBrandIcon(
      _provider(
        adapterId: 'http-json',
        name: 'Cursor',
        url: 'https://cursor.com/api/usage-summary',
      ).copyWith(kind: ManagedProviderKind.subscriptionQuota),
    ),
    const ManagedProviderBrandIconSpec.bundled('cursor'),
  );
});
```

Same for `api.anthropic.com` → claude, `chatgpt.com` → openai. DeepSeek host test stays.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/widgets/managed_provider/managed_provider_brand_icon_test.dart`

Expected: FAIL — Cursor URL falls through to initials.

- [ ] **Step 3: Write minimal implementation**

Remove `official-*-subscription` branches. After parsing host:

- `cursor.com` → `cursor`
- `api.anthropic.com` / name Claude → `claude`
- `chatgpt.com` → `openai`
- keep DeepSeek host/name
- then `brand.iconUrl` / initials

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/widgets/managed_provider/managed_provider_brand_icon_test.dart`

Expected: PASS

---

### Task 9: Delete official adapters and wire registry

**Files:**
- Delete:  
  `client/lib/services/provider_usage/adapters/claude_subscription_adapter.dart`  
  `client/lib/services/provider_usage/adapters/codex_subscription_adapter.dart`  
  `client/lib/services/provider_usage/adapters/cursor_subscription_adapter.dart`  
  `client/lib/services/provider_usage/adapters/claude_official_subscription_client.dart`  
  `client/lib/services/provider_usage/adapters/codex_official_subscription_client.dart`  
  `client/lib/services/provider_usage/adapters/cursor_official_subscription_client.dart`
- Keep auth readers. If `official_subscription_adapter.dart` only served those adapters, move `OfficialSubscriptionAuthReader` into `cli_credential_source.dart` and delete the rest (`OfficialSubscriptionClient`, windows types).
- Modify: `client/lib/app/app_shell.dart` — `buildDefaultManagedProviderUsageRegistry` only registers `HttpJsonMappingAdapter(cliCredentials: ...)`.
- Modify tests that import deleted types.

- [ ] **Step 1: Write the failing test**

In `app_shell_provider_usage_bootstrap_test.dart`:

```dart
test('default registry exposes http-json only', () {
  final registry = buildDefaultManagedProviderUsageRegistry();
  expect(registry.adapterFor('http-json'), isNotNull);
  expect(registry.adapterFor('official-claude-subscription'), isNull);
  expect(registry.adapterFor('official-codex-subscription'), isNull);
  expect(registry.adapterFor('official-cursor-subscription'), isNull);
});
```

Remove the loop that expected official adapters to fail closed as `unsupported`.

Delete or rewrite:

- `official_subscription_client_test.dart` (behavior now in http-json preset tests)
- `official_subscription_adapter_test.dart`

Keep `official_subscription_auth_test.dart`.

Widget tests that construct `adapterId: 'official-codex-subscription'` can keep that string only as a fake id for layout tests, or switch to `http-json` + chatgpt URL for icons. Prefer `http-json` + URL so icons still resolve.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/app/app_shell_provider_usage_bootstrap_test.dart --name "http-json only"`

Expected: FAIL — official adapters still registered.

- [ ] **Step 3: Write minimal implementation**

```dart
ManagedProviderUsageRegistry buildDefaultManagedProviderUsageRegistry({
  CliCredentialSourceResolver? cliCredentials,
}) {
  return ManagedProviderUsageRegistry([
    HttpJsonMappingAdapter(cliCredentials: cliCredentials),
  ]);
}
```

`buildAppShell` constructs:

```dart
CliCredentialSourceResolver(
  readers: {
    'claude-official': ClaudeOfficialSubscriptionAuthReader(...),
    'openai-official': CodexOfficialSubscriptionAuthReader(...),
    'cursor-account': CursorOfficialSubscriptionAuthReader(...),
  },
)
```

Remove `managedProviderClaudeAuthReader` / official client parameters or keep them only if tests inject a fake resolver — prefer one `cliCredentials` parameter.

Delete unused files. Fix analyzer imports.

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
cd client && flutter test \
  test/app/app_shell_provider_usage_bootstrap_test.dart \
  test/services/provider_usage/ \
  test/pages/managed_providers/managed_provider_management_page_test.dart \
  test/widgets/managed_provider/ \
  test/models/managed_provider_test.dart \
  test/models/managed_provider_editor_schema_test.dart
```

Expected: PASS

Then: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: no new issues in touched files.

---

### Task 10: Editor schema fields for new config

**Files:**
- Modify: `client/lib/models/managed_provider_editor_schema.dart`
- Modify: `client/lib/pages/managed_providers/` section that edits headers / field mappings (add windows + credentialSource + credentialTemplate JSON/text fields)
- Test: `client/test/models/managed_provider_editor_schema_test.dart`
- Test: management page — Cursor preset shows endpoint URL field (query section visible)

- [ ] **Step 1: Write the failing test**

```dart
test('http-json subscription preset exposes query and cli credential fields', () {
  final schema = ManagedProviderEditorSchema.fromProvider(
    managedProviderPresetById('cursor')!.template,
  );
  expect(schema.hasSection(ManagedProviderEditorSection.query), isTrue);
  expect(schema.hasField('endpointConfig.url'), isTrue);
  expect(schema.hasField('endpointConfig.credentialSource'), isTrue);
  expect(schema.hasField('endpointConfig.windows'), isTrue);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/managed_provider_editor_schema_test.dart --name "cli credential"`

Expected: FAIL — fields missing.

- [ ] **Step 3: Write minimal implementation**

When `_usesHttpEditor`, add fields:

- `endpointConfig.credentialSource` (text)
- `endpointConfig.credentialTemplate` (text)
- `endpointConfig.windows` (json)
- `endpointConfig.headers` if not already present

Wire controllers on the editor page so applying a preset fills them and saving writes them back onto `ManagedProviderEndpointConfig`.

If headers are already edited as JSON in the query section, reuse that control.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/models/managed_provider_editor_schema_test.dart test/pages/managed_providers/managed_provider_management_page_test.dart`

Expected: PASS

---

## Spec coverage

| Spec requirement | Task |
|------------------|------|
| `credentialSource` / `credentialTemplate` / `windows` model | 1 |
| Template + `{jwt.sub}` + accountId fill | 2 |
| Named windows + skip + `%` total 100 | 3 |
| `cli:<id>` file readers, no list scan | 4 |
| Header omit + Cookie compose + custom ≡ preset | 5 |
| Four presets are `http-json` fill-ins | 6 |
| Login bar on `cli:` only | 7 |
| Icons from host | 8 |
| Delete official adapters, registry http-json only | 9 |
| Editor can view/edit the filled fields | 10 |
| No old adapter migration | 9 (delete, no migrate) |
| DeepSeek unchanged | 3, 6 |

## Notes for the implementer

- `headers` JSON already strips Authorization-like secrets on save (`managed_provider_test`). Keep Cookie **values** in `credentialTemplate`, not in `headers`.
- Cursor On-demand/Team windows use raw used/total (cents). Do not add extra unit conversion.
- Do not reintroduce `official-*-subscription` aliases.
