# Managed Provider ↔ App Provider Credential Link Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let balance/usage entries ("余额与用量", `ManagedProvider`) and CLI provider configs ("供应商配置", `AppProviderConfig`) share one API key via live bidirectional references.

**Architecture:** A managed entry's `credentialSource` gains a third form `provider:<cli>:<providerId>` (alongside `secret` and `cli:<rowId>`), resolved at request time by extending `ManagedProviderCredentialResolver`. Conversely, `AppProviderConfig` gains a persisted `credentialLink` field naming a managed entry; the provider's apiKey is resolved in memory from `ManagedProviderSecretStore` at load/save and never persisted. Deletion cleanup and cycle guards are symmetric.

**Tech Stack:** Flutter/Dart, flutter_bloc, existing repositories (`AppProviderRepository`, `ManagedProviderRepository`), `ManagedProviderSecretStore` secure storage, l10n ARB files.

**Spec:** `docs/specs/2026-09-07-managed-provider-app-provider-credential-link-design.md`

## Global Constraints

- Scope is apiKey-class providers only: `AppProviderCategory.thirdParty`, `aggregator`, `cnOfficial` (i.e. `AppProviderConfig.requiresApiKey == true`). Official OAuth providers (claude/codex/cursor official rows) and the existing `cli:` source machinery are untouched.
- l10n: edit `client/lib/l10n/app_en.arb` and `client/lib/l10n/app_zh.arb` ONLY (generated `app_localizations*.dart` files are produced by the build — run `flutter gen-l10n` or let the test run regenerate).
- Never persist resolved linked secrets into `providers.json` — linked rows persist with empty `apiKey`.
- No `print`; diagnostics go to `AppLogger`.
- Full gate before done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Tests use `InMemoryFilesystem` (`client/test/support/in_memory_filesystem.dart`) and the `_FakeSecureKeyValueStore` pattern from `client/test/services/provider_usage/managed_provider_secret_store_test.dart`.

---

### Task 1: `AppProviderConfig.credentialLink` model field

**Files:**
- Modify: `client/lib/models/app_provider_config.dart` (constructor, `fromJson`, `_knownKeys`, fields, `copyWith`, `toJson`)
- Test: `client/test/models/app_provider_config_test.dart` (create if absent)

**Interfaces:**
- Produces: `AppProviderConfig.credentialLink` (`String`, default `''`), copyWith param `String? credentialLink`, JSON key `'credentialLink'`.

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';

void main() {
  test('credentialLink round-trips through json', () {
    const provider = AppProviderConfig(
      id: 'deepseek',
      cli: CliTool.claude,
      name: 'DeepSeek',
      credentialLink: 'managed-1',
    );
    final decoded = AppProviderConfig.fromJson(
      Map<String, Object?>.from(jsonDecode(jsonEncode(provider.toJson()))),
    );
    expect(decoded.credentialLink, 'managed-1');
  });

  test('credentialLink defaults to empty and does not serialize when empty',
      () {
    const provider = AppProviderConfig(
      id: 'x',
      cli: CliTool.claude,
      name: 'X',
    );
    expect(provider.credentialLink, '');
    expect(provider.toJson().containsKey('credentialLink'), isFalse);
    // Pre-feature files (no credentialLink key) round-trip unchanged.
    final decoded = AppProviderConfig.fromJson({
      'id': 'x',
      'cli': 'claude',
      'name': 'X',
    });
    expect(decoded.credentialLink, '');
  });

  test('copyWith updates and clears credentialLink', () {
    const provider = AppProviderConfig(
      id: 'x',
      cli: CliTool.claude,
      name: 'X',
      credentialLink: 'a',
    );
    expect(provider.copyWith(credentialLink: 'b').credentialLink, 'b');
    expect(provider.copyWith(credentialLink: '').credentialLink, '');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart test test/models/app_provider_config_test.dart`
Expected: FAIL — `credentialLink` is not a named parameter.

- [ ] **Step 3: Implement**

In `app_provider_config.dart`, mirroring the existing field style:

- Constructor: `this.credentialLink = '',` (place after `credentialUpdatedAt`).
- `fromJson`: `credentialLink: json['credentialLink'] as String? ?? '',`
- `_knownKeys`: add `'credentialLink'`.
- Field: `final String credentialLink;`
- `copyWith`: `String? credentialLink,` param, `credentialLink: credentialLink ?? this.credentialLink,` in the body.
- `toJson`: `if (credentialLink.isNotEmpty) 'credentialLink': credentialLink,`

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart test test/models/app_provider_config_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/app_provider_config.dart client/test/models/app_provider_config_test.dart
git commit -m "feat(providers): credentialLink field on AppProviderConfig"
```

---

### Task 2: `provider:` credential-source form helpers

**Files:**
- Create: `client/lib/services/provider_usage/managed_provider_link_binding.dart`
- Test: `client/test/services/provider_usage/managed_provider_link_binding_test.dart`

**Interfaces:**
- Produces:

```dart
/// Parsed `provider:<cli>:<providerId>` managed-provider credential source.
@immutable
class ManagedProviderLinkSource {
  final CliTool cli;
  final String providerId;
  String get value; // canonical 'provider:<cli>:<providerId>'
}

/// Parses `source`; null for `secret`, `cli:*`, or malformed values.
ManagedProviderLinkSource? managedProviderLinkSourceOf(String source);
/// Formats parts into the canonical source string.
String managedProviderLinkSourceValue(CliTool cli, String providerId);
/// True when [provider] uses a linked provider-config credential source.
bool isManagedProviderLinkedToProvider(ManagedProvider provider);
```

- Consumes: `CliTool` (from `models/team_config.dart`), `ManagedProvider` (Task 1 of spec — existing model).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/provider_usage/managed_provider_link_binding.dart';

void main() {
  test('parses canonical provider source', () {
    final parsed = managedProviderLinkSourceOf('provider:claude:deepseek');
    expect(parsed, isNotNull);
    expect(parsed!.cli, CliTool.claude);
    expect(parsed.providerId, 'deepseek');
    expect(parsed.value, 'provider:claude:deepseek');
  });

  test('round-trips through formatter', () {
    final value = managedProviderLinkSourceValue(CliTool.codex, 'a b');
    expect(managedProviderLinkSourceOf(value)!.value, value);
  });

  test('rejects secret, cli, and malformed sources', () {
    expect(managedProviderLinkSourceOf('secret'), isNull);
    expect(managedProviderLinkSourceOf('cli:cursor'), isNull);
    expect(managedProviderLinkSourceOf('provider:claude:'), isNull);
    expect(managedProviderLinkSourceOf('provider:claude'), isNull);
    expect(managedProviderLinkSourceOf('provider:'), isNull);
    expect(managedProviderLinkSourceOf(''), isNull);
  });

  test('detects linked provider on a ManagedProvider', () {
    ManagedProvider provider(String source) => ManagedProvider(
      id: 'p',
      name: 'P',
      kind: ManagedProviderKind.apiBalance,
      adapterId: 'http-json',
      endpointConfig: ManagedProviderEndpointConfig(credentialSource: source),
    );
    expect(
      isManagedProviderLinkedToProvider(provider('provider:claude:d1')),
      isTrue,
    );
    expect(isManagedProviderLinkedToProvider(provider('secret')), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart test test/services/provider_usage/managed_provider_link_binding_test.dart`
Expected: FAIL — file/class not found.

- [ ] **Step 3: Implement**

```dart
import 'package:flutter/foundation.dart';

import '../../models/managed_provider.dart';
import '../../models/team_config.dart';

/// Parsed `provider:<cli>:<providerId>` managed-provider credential source.
///
/// Ids may contain any non-colon characters (provider ids are user slugs);
/// everything after the second colon is the id.
@immutable
class ManagedProviderLinkSource {
  const ManagedProviderLinkSource({required this.cli, required this.providerId});

  final CliTool cli;
  final String providerId;

  String get value => managedProviderLinkSourceValue(cli, providerId);

  @override
  bool operator ==(Object other) =>
      other is ManagedProviderLinkSource &&
      other.cli == cli &&
      other.providerId == providerId;

  @override
  int get hashCode => Object.hash(cli, providerId);
}

String managedProviderLinkSourceValue(CliTool cli, String providerId) =>
    'provider:${cli.value}:$providerId';

ManagedProviderLinkSource? managedProviderLinkSourceOf(String source) {
  final trimmed = source.trim();
  if (!trimmed.startsWith('provider:')) return null;
  final rest = trimmed.substring('provider:'.length);
  final firstColon = rest.indexOf(':');
  if (firstColon <= 0) return null;
  final cli = CliTool.tryParse(rest.substring(0, firstColon));
  final providerId = rest.substring(firstColon + 1);
  if (cli == null || providerId.isEmpty) return null;
  return ManagedProviderLinkSource(cli: cli, providerId: providerId);
}

bool isManagedProviderLinkedToProvider(ManagedProvider provider) =>
    managedProviderLinkSourceOf(
      provider.endpointConfig.credentialSource,
    ) !=
    null;
```

Note: check `CliTool` for an existing `tryParse`/`parse` API first (`client/lib/models/team_config.dart`). If only `CliTool.parse(Object?, {CliTool fallback})` exists, use `CliTool.parse(name, fallback: ...)` scanning `CliTool.values` manually:

```dart
CliTool? _cliFor(String name) {
  for (final cli in CliTool.values) {
    if (cli.value == name) return cli;
  }
  return null;
}
```

and drop the `tryParse` reference.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart test test/services/provider_usage/managed_provider_link_binding_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/provider_usage/managed_provider_link_binding.dart client/test/services/provider_usage/managed_provider_link_binding_test.dart
git commit -m "feat(providers): provider:<cli>:<id> credential source form helpers"
```

---

### Task 3: Forward resolver — managed entry queries an app provider's apiKey

**Files:**
- Modify: `client/lib/services/provider_usage/managed_provider_secret_store.dart` (class `ManagedProviderCredentialResolver` only, at the bottom of the file)
- Modify: `client/lib/app/app_shell.dart:949` (wiring)
- Test: `client/test/services/provider_usage/managed_provider_credential_link_resolver_test.dart` (new)

**Interfaces:**
- Consumes: `managedProviderLinkSourceOf` (Task 2), `AppProviderRepository.findById` (existing).
- Produces:

```dart
class ManagedProviderCredentialResolver implements ProviderCredentialResolver {
  const ManagedProviderCredentialResolver(
    this._store, {
    AppProviderRepository? appProviders,
  });
}
```

`resolve(ManagedProvider)` returns a scope whose single field is the entry's `endpointConfig.credentialField ?? 'apiKey'` mapped to the referenced provider's `apiKey`. Missing provider / empty key → `null` (the http-json adapter already turns a null/empty scope into `missingCredential`).

- [ ] **Step 1: Write the failing test**

Follow the `_FakeSecureKeyValueStore` pattern from `managed_provider_secret_store_test.dart`; back `AppProviderRepository` with `InMemoryFilesystem` writing a `providers.json` (see `client/test/repositories/app_provider_repository_test.dart` for the JSON shape — the file is a map of `provider id -> provider.toJson()` under a top-level `'providers'` key).

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/provider_usage/managed_provider_link_binding.dart';
import 'package:teampilot/services/provider_usage/managed_provider_secret_store.dart';

import '../../support/in_memory_filesystem.dart';

class _FakeSecureKeyValueStore /* implements SecureKeyValueStore as in
    managed_provider_secret_store_test.dart */ {}

ManagedProvider _linkedEntry(CliTool cli, String providerId) =>
    ManagedProvider(
      id: 'm1',
      name: 'M1',
      kind: ManagedProviderKind.apiBalance,
      adapterId: 'http-json',
      endpointConfig: ManagedProviderEndpointConfig(
        credentialSource: managedProviderLinkSourceValue(cli, providerId),
        credentialField: 'apiKey',
      ),
    );

void main() {
  late InMemoryFilesystem fs;
  late AppProviderRepository repo;

  setUp(() {
    fs = InMemoryFilesystem();
    repo = AppProviderRepository(fs: fs, basePath: '/tp');
  });

  Future<void> seedProvider(
    CliTool cli,
    String id,
    String apiKey, {
    bool writeKey = true,
  }) async {
    final path = '/tp/providers/${cli.value}/providers.json';
    final provider = AppProviderConfig(
      id: id,
      cli: cli,
      name: 'Test',
      category: AppProviderCategory.thirdParty,
      apiKey: writeKey ? apiKey : '',
    );
    await fs.ensureDir('/tp/providers/${cli.value}');
    await fs.writeString(path, '{"providers":{"$id":${provider.toJson()}}}');
  }

  test('resolves provider source to the referenced apiKey', () async {
    await seedProvider(CliTool.claude, 'deepseek', 'sk-123');
    final resolver = ManagedProviderCredentialResolver(
      const _FakeSecureKeyValueStore(),
      appProviders: repo,
    );
    final scope = await resolver.resolve(_linkedEntry(CliTool.claude, 'deepseek'));
    expect(scope, isNotNull);
    expect(scope!.valueFor('apiKey'), 'sk-123');
  });

  test('missing provider or empty key resolves to null', () async {
    final resolver = ManagedProviderCredentialResolver(
      const _FakeSecureKeyValueStore(),
      appProviders: repo,
    );
    // No provider row at all.
    expect(
      await resolver.resolve(_linkedEntry(CliTool.claude, 'nope')),
      isNull,
    );
    // Provider row exists but key is blank.
    await seedProvider(CliTool.claude, 'empty', '', writeKey: false);
    expect(
      await resolver.resolve(_linkedEntry(CliTool.claude, 'empty')),
      isNull,
    );
  });

  test('secret sources still resolve through the secret store', () async {
    // A secret-backed entry keeps using the store (existing behavior).
    final store = ManagedProviderSecretStore(const _FakeSecureKeyValueStore());
    // (use the fake store map to write 'managed-provider:m1' / field 'apiKey')
    final resolver = ManagedProviderCredentialResolver(
      /* same fake store instance */ const _FakeSecureKeyValueStore(),
      appProviders: repo,
    );
    // ... assert resolver.resolve(secret entry) mirrors store contents
  });

  test('null appProviders repository leaves provider sources unresolved',
      () async {
    final resolver = ManagedProviderCredentialResolver(
      const _FakeSecureKeyValueStore(),
    );
    expect(
      await resolver.resolve(_linkedEntry(CliTool.claude, 'deepseek')),
      isNull,
    );
  });
}
```

 Flesh out the fake store and the third test fully (the fake store is a simple in-memory `Map<String, String>` implementing `read`/`write`/`delete`).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart test test/services/provider_usage/managed_provider_credential_link_resolver_test.dart`
Expected: FAIL — `appProviders` named parameter does not exist.

- [ ] **Step 3: Implement**

In `managed_provider_secret_store.dart`, extend the resolver at the bottom of the file (keep `const` constructibility — `AppProviderRepository` param stays optional; note `const` constructor cannot hold a non-const repository field typed as `AppProviderRepository` if it is not const-constructible, so drop `const` from the constructor if the analyzer requires it — the single call site in `app_shell.dart:949` then drops its `const` keyword too):

```dart
class ManagedProviderCredentialResolver implements ProviderCredentialResolver {
  ManagedProviderCredentialResolver(
    this._store, {
    AppProviderRepository? appProviders,
  }) : _appProviders = appProviders;

  final ManagedProviderSecretStore _store;
  final AppProviderRepository? _appProviders;

  @override
  Future<ProviderCredentialScope?> resolve(ManagedProvider provider) async {
    final link = managedProviderLinkSourceOf(
      provider.endpointConfig.credentialSource,
    );
    if (link != null) return _resolveLinkedProvider(link, provider);
    final ref = provider.credentialRef?.trim();
    if (ref == null || ref.isEmpty) return null;
    final credentials = await _store.read(ref);
    if (credentials.isEmpty) return null;
    return credentials;
  }

  Future<ProviderCredentialScope?> _resolveLinkedProvider(
    ManagedProviderLinkSource link,
    ManagedProvider provider,
  ) async {
    final repo = _appProviders;
    if (repo == null) return null;
    final AppProviderConfig? row;
    try {
      row = await repo.findById(link.cli, link.providerId);
    } on Object {
      return null;
    }
    if (row == null) return null;
    final apiKey = row.apiKey;
    if (apiKey.isEmpty) return null;
    final field = provider.endpointConfig.credentialField ?? 'apiKey';
    return ManagedProviderCredentialScope({field: apiKey});
  }
}
```

Add imports: `managed_provider_link_binding.dart` and `../../repositories/app_provider_repository.dart`.

Wiring in `app_shell.dart` (~line 949): the resolver must be constructed with a repository. `resolvedManagedProviderRepository` (line 908) and a default `AppProviderRepository()` both target the same disk; the coordinator is built before `appProviderCubit` (line 969) but the repository is independent — construct a dedicated instance for the resolver:

```dart
credentials: ManagedProviderCredentialResolver(
  resolvedManagedProviderSecretStore,
  appProviders: AppProviderRepository(),
),
```

(Note: `AppProviderRepository` uses `AppStorage.paths.basePath`, bound at line 893 — safe here.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart test test/services/provider_usage/managed_provider_credential_link_resolver_test.dart`
Expected: PASS.

Also run the existing resolver-related suites to catch regressions:
Run: `cd client && dart test test/services/provider_usage/managed_provider_usage_coordinator_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/provider_usage/managed_provider_secret_store.dart client/lib/app/app_shell.dart client/test/services/provider_usage/managed_provider_credential_link_resolver_test.dart
git commit -m "feat(providers): managed entries can query with an app provider apiKey"
```

---

### Task 4: Reverse resolver — provider config uses a managed entry's secret

**Files:**
- Modify: `client/lib/repositories/app_provider_repository.dart`
- Modify: `client/lib/app/app_shell.dart` (inject lookup into `AppProviderCubit`'s repository)
- Test: `client/test/repositories/app_provider_repository_credential_link_test.dart` (new)

**Interfaces:**
- Produces (in `app_provider_repository.dart`):

```dart
/// Returns the linked managed entry's secret value, or null when the entry
/// or its secret is missing. Injected by the app shell.
typedef LinkedCredentialLookup = Future<String?> Function(
  String managedProviderId,
);

class AppProviderRepository {
  AppProviderRepository({
    ...,
    LinkedCredentialLookup? linkedCredentialLookup,
  });
}
```

Behavior:
1. `saveProviders` never persists a resolved linked key: linked rows (`credentialLink` non-empty) are persisted with `apiKey: ''`, and `_mergePreservedSecrets` skips preserving an old key for linked rows (the link replaces the key).
2. `loadProviders` / `reconcileProviders` return in-memory copies where linked rows have `apiKey` filled from the lookup and `credentialStatus` set to `ready`/`missing` accordingly. Disk stays clean.
3. `reconcileSaved` (native config materialization, e.g. flashskyai `llm_config.json`) receives the resolved copies.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';

import '../support/in_memory_filesystem.dart';

AppProviderConfig _linkedRow() => const AppProviderConfig(
  id: 'deepseek',
  cli: CliTool.claude,
  name: 'DeepSeek',
  category: AppProviderCategory.thirdParty,
  credentialLink: 'm1',
);

void main() {
  late InMemoryFilesystem fs;
  String? linkedSecret;

  setUp(() {
    fs = InMemoryFilesystem();
    linkedSecret = null;
  });

  AppProviderRepository repo() => AppProviderRepository(
    fs: fs,
    basePath: '/tp',
    linkedCredentialLookup: (id) async =>
        id == 'm1' ? linkedSecret : null,
  );

  test('load resolves linked apiKey in memory without persisting it',
      () async {
    linkedSecret = 'sk-live';
    final r = repo();
    await r.saveProviders(CliTool.claude, [_linkedRow()]);
    final loaded = await r.loadProviders(CliTool.claude);
    expect(loaded.single.apiKey, 'sk-live');
    expect(loaded.single.credentialStatus, 'ready');
    // Disk keeps the linked row's key empty.
    final raw = await fs.readString('/tp/providers/claude/providers.json');
    expect(raw, isNotNull);
    expect(raw!.contains('sk-live'), isFalse);
    expect(raw.contains('"credentialLink": "m1"'), isTrue);
  });

  test('missing managed secret yields empty key and missing status', () async {
    linkedSecret = null; // entry or secret absent
    final r = repo();
    await r.saveProviders(CliTool.claude, [_linkedRow()]);
    final loaded = await r.loadProviders(CliTool.claude);
    expect(loaded.single.apiKey, '');
    expect(loaded.single.credentialStatus, 'missing');
  });

  test('save strips a stale resolved key on a linked row', () async {
    final r = repo();
    await r.saveProviders(CliTool.claude, [_linkedRow()]);
    // Simulate a caller handing back the in-memory-resolved row.
    final loaded = await r.loadProviders(CliTool.claude);
    await r.saveProviders(CliTool.claude, loaded);
    final raw = await fs.readString('/tp/providers/claude/providers.json');
    expect(raw!.contains('"apiKey": "sk'), isFalse);
  });

  test('unlinked providers keep preserved-secret merge behavior', () async {
    final r = repo();
    const withKey = AppProviderConfig(
      id: 'plain',
      cli: CliTool.claude,
      name: 'Plain',
      category: AppProviderCategory.thirdParty,
      apiKey: 'sk-own',
    );
    await r.saveProviders(CliTool.claude, [withKey]);
    final loaded = await r.loadProviders(CliTool.claude);
    // Blank key on an unlinked row preserves the stored secret (existing rule).
    await r.saveProviders(
      CliTool.claude,
      [loaded.single.copyWith(apiKey: '')],
    );
    final reloaded = await r.loadProviders(CliTool.claude);
    expect(reloaded.single.apiKey, 'sk-own');
  });

  test('linked rows materialize native config with the resolved key',
      () async {
    // Flashskyai materializes cli-defaults/flashskyai/llm_config.json on save.
    linkedSecret = 'sk-live';
    final r = AppProviderRepository(
      fs: fs,
      basePath: '/tp',
      linkedCredentialLookup: (id) async => id == 'm1' ? 'sk-live' : null,
    );
    await r.saveProviders(
      CliTool.flashskyai,
      [
        _linkedRow().copyWith(cli: CliTool.flashskyai, baseUrl: 'https://x'),
      ],
    );
    final raw = await fs.readString(
      '/tp/cli-defaults/flashskyai/llm_config.json',
    );
    expect(raw, isNotNull);
    expect(raw!.contains('sk-live'), isTrue);
  });
}
```

(If the flashskyai file path differs, check `RuntimeLayout.appFlashskyaiLlmConfigFile` — adjust the assertion path to what that resolves to under `/tp`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart test test/repositories/app_provider_repository_credential_link_test.dart`
Expected: FAIL — `linkedCredentialLookup` parameter does not exist.

- [ ] **Step 3: Implement**

In `app_provider_repository.dart`:

1. Add the typedef and constructor field (`_linkedCredentialLookupOverride`-style, mirroring `_fsOverride` — but this is a function, so store directly):

```dart
typedef LinkedCredentialLookup =
    Future<String?> Function(String managedProviderId);
```

2. Add a private resolution helper:

```dart
/// In-memory apiKey + status resolution for credential-linked providers.
/// Linked rows never persist the resolved key (see [_stripLinkedApiKey]).
Future<List<AppProviderConfig>> _resolveLinkedCredentials(
  List<AppProviderConfig> providers,
) async {
  final lookup = _linkedCredentialLookup;
  if (lookup == null) return providers;
  await Future.wait(providers.map((provider) async { /* see below */ }));
  // ... implement as: build a new list where each linked provider with an
  // empty persisted apiKey gets the lookup value (or '' when missing) and
  // credentialStatus 'ready'/'missing'. Unlinked providers pass through.
}
```

Concrete implementation:

```dart
Future<List<AppProviderConfig>> _resolveLinkedCredentials(
  List<AppProviderConfig> providers,
) async {
  final lookup = _linkedCredentialLookup;
  if (lookup == null) return providers;
  final resolved = <AppProviderConfig>[];
  for (final provider in providers) {
    final link = provider.credentialLink.trim();
    if (link.isEmpty) {
      resolved.add(provider);
      continue;
    }
    String? secret;
    try {
      secret = await lookup(link);
    } on Object {
      secret = null;
    }
    resolved.add(
      provider.copyWith(
        apiKey: secret ?? '',
        credentialStatus: secret == null || secret.isEmpty
            ? 'missing'
            : 'ready',
      ),
    );
  }
  return resolved;
}

AppProviderConfig _stripLinkedApiKey(AppProviderConfig provider) {
  if (provider.credentialLink.trim().isEmpty) return provider;
  if (provider.apiKey.isEmpty) return provider;
  return provider.copyWith(apiKey: '');
}
```

3. `_mergePreservedSecrets`: skip preservation for linked rows:

```dart
static AppProviderConfig _mergePreservedSecrets(
  AppProviderConfig provider,
  AppProviderConfig? previous,
) {
  if (previous == null) return _stripLinkedApiKey(provider);
  if (provider.credentialLink.trim().isNotEmpty) {
    // A link replaces the stored key — never preserve the old one.
    return _stripLinkedApiKey(provider);
  }
  if (provider.apiKey.isNotEmpty || previous.apiKey.isEmpty) {
    return provider;
  }
  return provider.copyWith(apiKey: previous.apiKey);
}
```

4. `saveProviders`: after computing `merged`, persist the stripped list, then pass the resolved list to strategies:

```dart
final merged = [ ... as today ... ];
final persisted = [for (final p in merged) _stripLinkedApiKey(p)];
// ... encode + atomicWrite `persisted` (replacing today's `merged`) ...
_invalidateDiskCache(cli);
final resolved = await _resolveLinkedCredentials(persisted);
await _strategies[cli]?.reconcileSaved(_persistenceContext, resolved);
```

(Note the disk-cache must be invalidated before `_resolveLinkedCredentials` re-reads — `findById` inside flows uses `loadProviders`.)

5. `loadProviders`: resolve after reconciliation:

```dart
Future<List<AppProviderConfig>> loadProviders(...) async {
  var providers = await _loadProvidersFromDisk(cli);
  if (!reconcileCredentials) return _resolveLinkedCredentials(providers);
  final reconciled = await reconcileProviders(
    cli,
    providers,
    importCredentialsFromGlobal: importCredentialsFromGlobal,
  );
  return _resolveLinkedCredentials(reconciled);
}
```

6. `reconcileProviders` (public): append resolution at its return too, so `AppProviderCubit.reconcileCredentials()` sees linked keys:

```dart
return _resolveLinkedCredentials(
  await strategy.reconcileLoaded(_persistenceContext, providers),
);
```

Guard against double-resolution: `_resolveLinkedCredentials` on an already-resolved row re-runs the lookup — acceptable (idempotent) but avoid unbounded churn by returning early when every provider is either unlinked or already `ready`/`missing` with a non-empty apiKey... simplest: keep it idempotent (lookup result is the same) and rely on the cubit's equality checks. Note the resolution happens once per load, not per build.

Wiring in `app_shell.dart` (~line 969, `AppProviderCubit` construction): `AppProviderCubit` builds its own `AppProviderRepository()` by default. Add an optional `AppProviderRepository? repository` is already there — so instead inject at the construction site:

```dart
final appProviderLinkedCredentialLookup = LinkedCredentialLookup(
  // reads managed entry's stored secret (spec: reverse direction)
  (managedProviderId) async {
    final entries = await resolvedManagedProviderRepository.load();
    final entry = entries
        .where((e) => e.id == managedProviderId)
        .firstOrNull;
    if (entry == null) return null;
    final ref = entry.credentialRef?.trim();
    if (ref == null || ref.isEmpty) return null;
    final scope = await resolvedManagedProviderSecretStore.read(ref);
    final field = entry.endpointConfig.credentialField ?? 'apiKey';
    final value = scope.valueFor(field);
    return (value == null || value.isEmpty) ? null : value;
  },
);

appProviderCubit = AppProviderCubit(
  repository: AppProviderRepository(
    linkedCredentialLookup: appProviderLinkedCredentialLookup,
  ),
  flashskyaiExecutablePath: ...,
  openCredentialLoginUrl: ...,
);
```

(Place the lookup closure after `resolvedManagedProviderRepository`/`resolvedManagedProviderSecretStore` are defined — both exist by line 908 — and before line 969. Keep the closure secret-free in logs.)

- [ ] **Step 4: Run tests**

Run: `cd client && dart test test/repositories/app_provider_repository_credential_link_test.dart test/repositories/app_provider_repository_test.dart`
Expected: PASS both (existing suite confirms no regression in merge/probe behavior).

- [ ] **Step 5: Commit**

```bash
git add client/lib/repositories/app_provider_repository.dart client/lib/app/app_shell.dart client/test/repositories/app_provider_repository_credential_link_test.dart
git commit -m "feat(providers): provider configs can use a managed entry secret via credentialLink"
```

---

### Task 5: Cycle guards on both save paths

**Files:**
- Modify: `client/lib/cubits/managed_provider_cubit.dart` (`upsert`)
- Modify: `client/lib/cubits/app_provider_cubit.dart` (`upsertProvider`)
- Test: `client/test/cubits/managed_provider_cubit_credential_link_test.dart` (new)
- Test: extend `client/test/cubits/app_provider_cubit_test.dart`

**Interfaces:**
- Consumes: `managedProviderLinkSourceOf` (Task 2), `AppProviderConfig.credentialLink` (Task 1), `ManagedProviderRepository` (existing).
- Produces: `AppProviderCubit` gains optional constructor param `ManagedProviderRepository? managedProviderRepository`; `ManagedProviderCubit.upsert` rejects cycles with the existing `saveFailed` error code; `AppProviderCubit.upsertProvider` returns `false` on a cycle.

A cycle is: managed entry M with source `provider:<cli>:<P>` while provider P has `credentialLink == M.id`.

- [ ] **Step 1: Write the failing tests**

`managed_provider_cubit_credential_link_test.dart` (follow the setup pattern of `managed_provider_cubit_test.dart` — `InMemoryFilesystem`, two repositories sharing it):

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/managed_provider_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/services/provider_usage/managed_provider_link_binding.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late ManagedProviderCubit managedCubit;
  late AppProviderCubit appCubit;

  setUp(() {
    fs = InMemoryFilesystem();
    final appRepo = AppProviderRepository(fs: fs, basePath: '/tp');
    final managedRepo = ManagedProviderRepository(
      fs: fs,
      configPath: '/tp/managed-providers.json',
      onProvidersDeleted: (_) async {},
    );
    appCubit = AppProviderCubit(repository: appRepo, basePath: '/tp');
    managedCubit = ManagedProviderCubit(
      repository: managedRepo,
      appProviderCubit: appCubit,
    );
  });

  tearDown(() async {
    await managedCubit.close();
    await appCubit.close();
  });

  ManagedProvider _entry(String id, String source) => ManagedProvider(
    id: id,
    name: 'Entry $id',
    kind: ManagedProviderKind.apiBalance,
    adapterId: 'http-json',
    endpointConfig: ManagedProviderEndpointConfig(credentialSource: source),
  );

  test('rejects a managed entry that links a provider which links back',
      () async {
    // Provider deepseek has credentialLink -> m1.
    await appCubit.upsertProvider(
      const AppProviderConfig(
        id: 'deepseek',
        cli: CliTool.claude,
        name: 'DeepSeek',
        category: AppProviderCategory.thirdParty,
        credentialLink: 'm1',
      ),
    );
    await managedCubit.upsert(
      _entry('m1', managedProviderLinkSourceValue(CliTool.claude, 'deepseek')),
    );
    // The cycle-forming upsert was rejected: entry not persisted.
    expect(managedCubit.state.providerFor('m1'), isNull);
    expect(
      managedCubit.state.errorCode,
      ManagedProviderErrorCode.saveFailed,
    );
  });

  test('accepts a link when the provider has no back-link', () async {
    await appCubit.upsertProvider(
      const AppProviderConfig(
        id: 'deepseek',
        cli: CliTool.claude,
        name: 'DeepSeek',
        category: AppProviderCategory.thirdParty,
      ),
    );
    await managedCubit.upsert(
      _entry('m1', managedProviderLinkSourceValue(CliTool.claude, 'deepseek')),
    );
    expect(managedCubit.state.providerFor('m1'), isNotNull);
    expect(managedCubit.state.errorCode, isNull);
  });
}
```

For `app_provider_cubit_test.dart`, add an analogous pair: construct `AppProviderCubit` with `managedProviderRepository` pointing at a `ManagedProviderRepository` seeded with entry `m1` whose source is `provider:claude:deepseek`; `upsertProvider` of a `deepseek` row with `credentialLink: 'm1'` returns `false` and does not persist; the same row without a conflicting managed entry persists fine.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart test test/cubits/managed_provider_cubit_credential_link_test.dart`
Expected: FAIL — cycle upsert currently succeeds and persists.

- [ ] **Step 3: Implement**

`managed_provider_cubit.dart`, at the top of `upsert` (after the empty-id check, before `_bindIntentSource`):

```dart
final link = managedProviderLinkSourceOf(
  trimmed.endpointConfig.credentialSource,
);
if (link != null) {
  final appCubit = _appProviderCubit;
  if (appCubit != null) {
    final row = appCubit.state
        .providersFor(link.cli)
        .where((p) => p.id == link.providerId)
        .firstOrNull;
    if (row != null && row.credentialLink.trim() == trimmed.id) {
      if (!isClosed) {
        emit(
          state.copyWith(
            status: ManagedProviderLoadStatus.error,
            errorCode: ManagedProviderErrorCode.saveFailed,
            errorMessage: null,
          ),
        );
      }
      return;
    }
  }
}
```

Import `managed_provider_link_binding.dart`.

`app_provider_cubit.dart`: add constructor param `ManagedProviderRepository? managedProviderRepository` (stored, default null). At the top of `upsertProvider` (after the empty-id check):

```dart
final link = provider.credentialLink.trim();
if (link.isNotEmpty) {
  final managedRepo = _managedProviderRepository;
  if (managedRepo != null) {
    final entries = await managedRepo.load();
    final entry = entries.where((e) => e.id == link).firstOrNull;
    if (entry != null &&
        managedProviderLinkSourceOf(
              entry.endpointConfig.credentialSource,
            )?.providerId ==
            trimmedId) {
      return false;
    }
  }
}
```

Import both `managed_provider_link_binding.dart` and `repositories/managed_provider_repository.dart`.

Wiring in `app_shell.dart` (~line 969): pass `managedProviderRepository: resolvedManagedProviderRepository` to `AppProviderCubit(...)`.

- [ ] **Step 4: Run tests**

Run: `cd client && dart test test/cubits/managed_provider_cubit_credential_link_test.dart test/cubits/app_provider_cubit_test.dart test/cubits/managed_provider_cubit_test.dart`
Expected: PASS all.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/managed_provider_cubit.dart client/lib/cubits/app_provider_cubit.dart client/lib/app/app_shell.dart client/test/cubits/managed_provider_cubit_credential_link_test.dart client/test/cubits/app_provider_cubit_test.dart
git commit -m "feat(providers): cycle guard for credential links on both save paths"
```

---

### Task 6: Link janitor — clear `credentialLink` when a managed entry is deleted

**Files:**
- Create: `client/lib/services/provider_usage/managed_provider_link_janitor.dart`
- Modify: `client/lib/app/app_shell.dart` (~line 991, `onProviderDeletedCredentialCleanup` closure)
- Test: `client/test/services/provider_usage/managed_provider_link_janitor_test.dart` (new)

**Interfaces:**
- Consumes: `AppProviderCubit.removeProviderRow` is NOT used — the janitor edits rows in place (clearing only the link), so it needs `AppProviderCubit.upsertProvider`.
- Produces:

```dart
class ManagedProviderLinkJanitor {
  ManagedProviderLinkJanitor({required AppProviderCubit appProviderCubit});
  /// Clears `credentialLink` on every provider row referencing
  /// [managedProviderId]. Best-effort: failures are logged, never thrown.
  Future<void> clearLinksFor(String managedProviderId);
}
```

Per spec, deleting an app provider row leaves managed entries alone (their next refresh fails with `missingCredential` — free from Task 3's null scope).

- [ ] **Step 1: Write the failing test**

Follow the harness of `managed_provider_cli_row_janitor_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/provider_usage/managed_provider_link_janitor.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late AppProviderCubit appCubit;

  setUp(() {
    fs = InMemoryFilesystem();
    appCubit = AppProviderCubit(
      repository: AppProviderRepository(fs: fs, basePath: '/tp'),
      basePath: '/tp',
    );
  });

  tearDown(() async {
    await appCubit.close();
  });

  test('clears credentialLink on rows referencing the deleted entry',
      () async {
    await appCubit.upsertProvider(
      const AppProviderConfig(
        id: 'deepseek',
        cli: CliTool.claude,
        name: 'DeepSeek',
        category: AppProviderCategory.thirdParty,
        credentialLink: 'm1',
      ),
    );
    await appCubit.upsertProvider(
      const AppProviderConfig(
        id: 'other',
        cli: CliTool.claude,
        name: 'Other',
        category: AppProviderCategory.thirdParty,
        credentialLink: 'm2',
      ),
    );

    await ManagedProviderLinkJanitor(
      appProviderCubit: appCubit,
    ).clearLinksFor('m1');

    final rows = appCubit.state.providersFor(CliTool.claude);
    expect(rows.singleWhere((p) => p.id == 'deepseek').credentialLink, '');
    expect(rows.singleWhere((p) => p.id == 'other').credentialLink, 'm2');
  });

  test('no-op when nothing references the entry', () async {
    await ManagedProviderLinkJanitor(
      appProviderCubit: appCubit,
    ).clearLinksFor('nobody');
    expect(appCubit.state.providersFor(CliTool.claude), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart test test/services/provider_usage/managed_provider_link_janitor_test.dart`
Expected: FAIL — file/class not found.

- [ ] **Step 3: Implement**

```dart
import 'dart:async';

import '../../cubits/app_provider_cubit.dart';
import '../../utils/logging/logger.dart';

/// Clears `credentialLink` references to a deleted managed-provider entry.
///
/// Owned by the managed-provider delete hook. Best-effort: failures are
/// logged and never propagate to the delete flow.
class ManagedProviderLinkJanitor {
  ManagedProviderLinkJanitor({required AppProviderCubit appProviderCubit})
    : _appProviderCubit = appProviderCubit;

  final AppProviderCubit _appProviderCubit;

  Future<void> clearLinksFor(String managedProviderId) async {
    final id = managedProviderId.trim();
    if (id.isEmpty) return;
    for (final cli in CliTool.values) {
      final List<AppProviderConfig> rows;
      try {
        rows = await _appProviderCubit.loadProvidersFor(cli);
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[managed-provider] link janitor failed to load ${cli.value} rows: $error',
          error: error,
          stackTrace: stackTrace,
        );
        continue;
      }
      for (final row in rows) {
        if (row.credentialLink.trim() != id) continue;
        try {
          await _appProviderCubit.upsertProvider(
            row.copyWith(credentialLink: ''),
          );
        } on Object catch (error, stackTrace) {
          appLogger.w(
            '[managed-provider] link janitor failed to clear link on '
            '${cli.value}/${row.id}: $error',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }
  }
}
```

Imports: `../../models/app_provider_config.dart`, `../../models/team_config.dart` (for `CliTool`).

Wiring in `app_shell.dart`: extend the existing `onProviderDeletedCredentialCleanup` closure (line ~991) — after the secret-store delete, run the janitor:

```dart
onProviderDeletedCredentialCleanup: (provider) async {
  final ref = provider.credentialRef?.trim();
  if (ref != null && ref.isNotEmpty) {
    await resolvedManagedProviderSecretStore.delete(ref);
  }
  await ManagedProviderLinkJanitor(
    appProviderCubit: appProviderCubit,
  ).clearLinksFor(provider.id);
},
```

- [ ] **Step 4: Run tests**

Run: `cd client && dart test test/services/provider_usage/managed_provider_link_janitor_test.dart test/services/provider_usage/managed_provider_cli_row_janitor_test.dart`
Expected: PASS all.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/provider_usage/managed_provider_link_janitor.dart client/lib/app/app_shell.dart client/test/services/provider_usage/managed_provider_link_janitor_test.dart
git commit -m "feat(providers): clear provider credentialLink when its managed entry is deleted"
```

---

### Task 7: Managed-provider editor UI — pick an app provider as credential source

**Files:**
- Modify: `client/lib/pages/managed_providers/managed_provider_editor_page.dart`
- Modify: `client/lib/pages/managed_providers/managed_provider_editor_sections.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/managed_providers/managed_provider_editor_credential_link_test.dart` (new)

**Interfaces:**
- Consumes: `managedProviderLinkSourceOf` / `managedProviderLinkSourceValue` (Task 2), `AppProviderCubit` (in widget tree via `context.read<AppProviderCubit>()`), `AppProviderConfig.requiresApiKey` (existing).
- Produces: editor state `_linkedProviderSource` derived from `_credentialSource.text`; a picker row keyed `managed-provider-credential-link` in the credentials section; secret field hidden when linked.

l10n keys (add to BOTH arb files; names use the `managedProviders*` prefix):

| Key | en | zh |
|-----|----|----|
| `managedProvidersCredentialLinkMode` | Credential source mode | 凭据来源方式 |
| `managedProvidersCredentialLinkManual` | Enter secret manually | 手动输入密钥 |
| `managedProvidersCredentialLinkPick` | Reference provider config | 引用供应商配置 |
| `managedProvidersCredentialLinkedTo` | Using credential of {provider} | 使用 {provider} 的凭证 |
| `managedProvidersCredentialLinkEmpty` | No API-key providers configured yet | 还没有可引用的供应商配置 |

- [ ] **Step 1: Write the failing test**

Widget test mirroring the harness of existing managed-provider editor tests (find one under `client/test/pages/managed_providers/` for the exact `_wrapEditor` helper — pump `ManagedProviderEditorPage` inside `MaterialApp` + `MultiBlocProvider`/`MultiRepositoryProvider` providing `AppProviderCubit` and `ManagedProviderSecretStore`):

```dart
testWidgets('selecting a provider link sets the credential source and hides the secret field',
    (tester) async {
  await tester.pumpWidget(_wrapEditor()); // existing helper pattern

  // Choose "Reference provider config" in the mode picker.
  await tester.tap(find.byKey(const Key('managed-provider-credential-link')));
  await tester.pumpAndSettle();

  // The secret input is replaced by a read-only chip naming the provider.
  expect(find.byKey(const Key('managed-provider-credential-secret')), findsNothing);
  expect(find.byKey(const Key('managed-provider-credential-link-chip')), findsOneWidget);
});
```

 flesh out: seed `AppProviderCubit` (in-memory fs) with one third-party claude row before pumping; assert the chip shows the provider name; then save and assert the persisted entry's `credentialSource` equals `provider:claude:<rowId>` (via `ManagedProviderCubit.state` or repository read).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart test test/pages/managed_providers/managed_provider_editor_credential_link_test.dart`
Expected: FAIL — key `managed-provider-credential-link` not found.

- [ ] **Step 3: Implement**

Editor page (`managed_provider_editor_page.dart`):

1. Getter next to `_isCliCredentialSource`:

```dart
bool get _isLinkedProviderSource =>
    managedProviderLinkSourceOf(_credentialSource.text.trim()) != null;
```

2. In `build`, extend the credentials-section child branch: when `_isLinkedProviderSource`, render a new `ManagedProviderLinkedCredentials` widget (read-only chip) in place of `ManagedProviderCredentialsSection` — mirroring how `_isCliCredentialSource` swaps in `ManagedProviderOfficialCredentials`:

```dart
child: _isCliCredentialSource
    ? ManagedProviderOfficialCredentials(...)
    : _isLinkedProviderSource
        ? ManagedProviderLinkedCredentials(
            source: managedProviderLinkSourceOf(
              _credentialSource.text.trim(),
            )!,
            providerName: _linkedProviderRowName(context),
          )
        : ManagedProviderCredentialsSection(...),
```

3. Above that branch (visible in non-cli mode), add the mode picker. Add a `TpSelectFormField<String>` (follow `TpSelectFormField` usage in `cli_preset_edit_dialog.dart:190`) as the first child of the credentials section, wired to a new callback:

```dart
// options: '' (manual) + 'provider:<cli>:<id>' for every apiKey-class row
List<(String value, String label)> _credentialLinkOptions(
  BuildContext context,
) {
  final appCubit = context.read<AppProviderCubit>();
  final options = <(String, String)>[
    ('', context.l10n.managedProvidersCredentialLinkManual),
  ];
  for (final cli in CliTool.values) {
    for (final row in appCubit.state.providersFor(cli)) {
      if (!row.requiresApiKey) continue;
      // Cycle guard: exclude rows that link back to this entry.
      if (row.credentialLink.trim() == _entryId) continue;
      options.add((
        managedProviderLinkSourceValue(cli, row.id),
        '${row.name} (${cli.value})',
      ));
    }
  }
  return options;
}

void _handleCredentialLinkModeChanged(String value) {
  setState(() {
    _credentialSource.text = value.isEmpty ? 'secret' : value;
    if (value.isNotEmpty) _credentialSecret.clear();
  });
}
```

The picker renders when the schema allows editing `endpointConfig.credentialSource` (same condition as the existing source field) and the current value maps to the option list (fall back to `''` when the source is unknown).

4. Hide the secret input in the Basics section when linked: in `ManagedProviderBasicsSection`, gate `_hasRequiredSecret(schema)` — pass a new `hideSecret` boolean from the page (`hideSecret: _isLinkedProviderSource || _isCliCredentialSource`). Note `_isCliCredentialSource` already hides it via schema flow; the explicit flag makes linked mode deterministic.

5. In `_save()`: skip the "required secret" validation and the `credentialRef` allocation when `_isLinkedProviderSource` is true (the linked flow needs neither a stored secret nor a ref). The entry persists with `credentialSource: 'provider:...'`, `credentialRef: null`.

Sections file (`managed_provider_editor_sections.dart`): add `ManagedProviderLinkedCredentials` (stateless, read-only):

```dart
class ManagedProviderLinkedCredentials extends StatelessWidget {
  const ManagedProviderLinkedCredentials({
    required this.source,
    required this.providerName,
    super.key,
  });

  final ManagedProviderLinkSource source;
  final String providerName;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      key: const Key('managed-provider-credential-link-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.link_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              providerName.isEmpty
                  ? l10n.managedProvidersCredentialLinkEmpty
                  : l10n.managedProvidersCredentialLinkedTo(providerName),
              ),
          ),
        ],
      ),
    );
  }
}
```

`_linkedProviderRowName(BuildContext)` in the page resolves the row name from `AppProviderCubit.state` (empty string when the row vanished — the chip then shows the "empty" copy).

l10n: add the five keys to both ARB files with `"@key"` placeholders as needed (`managedProvidersCredentialLinkedTo` takes a `{provider}` parameter; add the matching `placeholders` block as neighboring parameterized keys do).

- [ ] **Step 4: Run tests**

Run: `cd client && dart test test/pages/managed_providers/managed_provider_editor_credential_link_test.dart`
Expected: PASS. Also run any existing editor tests in that directory to catch wiring regressions.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/managed_providers/managed_provider_editor_page.dart client/lib/pages/managed_providers/managed_provider_editor_sections.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/pages/managed_providers/managed_provider_editor_credential_link_test.dart
git commit -m "feat(providers): managed provider editor can reference an app provider credential"
```

---

### Task 8: App-provider form UI — pick a managed entry as apiKey source

**Files:**
- Modify: `client/lib/widgets/app_provider/app_provider_form_sheet.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/widgets/app_provider/app_provider_form_credential_link_test.dart` (new)

**Interfaces:**
- Consumes: `ManagedProviderCubit` (in widget tree from `app_shell.dart:2851`), `ManagedProvider.credentialRef`/`endpointConfig.credentialSource` (existing), `AppProviderConfig.credentialLink` (Task 1).
- Produces: form draft carries `credentialLink`; apiKey input hidden when linked; picker keyed `app-provider-credential-link`.

l10n keys (add to BOTH arb files):

| Key | en | zh |
|-----|----|----|
| `appProviderCredentialLinkMode` | API key source | API Key 来源 |
| `appProviderCredentialLinkOwnKey` | Use own API key | 使用自己的 API Key |
| `appProviderCredentialLinkPick` | Reference balance & usage entry | 引用余额与用量条目 |
| `appProviderCredentialLinkedTo` | Using secret of {entry} | 使用 {entry} 的密钥 |
| `appProviderCredentialLinkEmpty` | No secret-backed balance entries yet | 还没有存有密钥的余额条目 |

- [ ] **Step 1: Write the failing test**

Extend the harness of `client/test/widgets/app_provider/app_provider_form_test.dart` (`_wrapForm` + `AppProviderCubit`), additionally providing `ManagedProviderCubit` (in-memory repository) seeded with an `apiBalance` entry `m1` that has `credentialRef: 'managed-provider:m1'`:

```dart
testWidgets('linking a managed entry hides the apiKey input', (tester) async {
  await tester.pumpWidget(_wrapFormWithManagedCubit());

  await tester.tap(find.byKey(const Key('app-provider-credential-link')));
  await tester.pumpAndSettle();

  expect(find.text(l10n.appProviderCredentialLinkedTo('Entry m1')), findsOneWidget);
  // Own-key input is hidden while linked.
  expect(find.widgetWithText(TextField, l10n.apiKey), findsNothing);
});
```

 Also assert: saving produces a draft whose `credentialLink == 'm1'` and `apiKey` empty (capture via `onSaved`); switching back to "own key" restores the input.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart test test/widgets/app_provider/app_provider_form_credential_link_test.dart`
Expected: FAIL — key not found.

- [ ] **Step 3: Implement**

In `app_provider_form_sheet.dart`:

1. State: `String _credentialLink = '';` — init from `widget.existing?.credentialLink ?? ''` in the init block (reset to `''` in `_syncStateForCli`).

2. Candidate list (exclude cycles: entries whose source references THIS provider's id — relevant when editing):

```dart
List<(String value, String label)> _credentialLinkOptions(BuildContext context) {
  final l10n = context.l10n;
  final managed = context.read<ManagedProviderCubit>().state.providers;
  final ownId = widget.existing?.id ?? '';
  final options = <(String, String)>[
    ('', l10n.appProviderCredentialLinkOwnKey),
  ];
  for (final entry in managed) {
    final ref = entry.credentialRef?.trim() ?? '';
    if (ref.isEmpty) continue;
    if (entry.kind != ManagedProviderKind.apiBalance &&
        entry.kind != ManagedProviderKind.customHttp) {
      continue;
    }
    final backLink = managedProviderLinkSourceOf(
      entry.endpointConfig.credentialSource,
    );
    if (backLink != null && backLink.providerId == ownId) continue;
    options.add((entry.id, entry.name));
  }
  return options;
}
```

Only show the picker when the draft is apiKey-class (`category` in thirdParty/aggregator/cnOfficial — check `_category` state; skip for official rows) and the CLI's capability does not already hide key fields.

3. Render the picker above the apiKey field using `TpSelectFormField<String>` (follow the usage pattern at `cli_preset_edit_dialog.dart:190`); on change:

```dart
setState(() {
  _credentialLink = value;
  if (value.isNotEmpty) _apiKeyCtl.clear();
});
```

When `_credentialLink` is non-empty, hide the apiKey `TextField` and show a read-only chip (`Key('app-provider-credential-link-chip')`) with `l10n.appProviderCredentialLinkedTo(entryName)`.

4. Draft construction (~line 226): add `credentialLink: _credentialLink,` and change `apiKey: _apiKeyCtl.text.trim(),` to `apiKey: _credentialLink.isNotEmpty ? '' : _apiKeyCtl.text.trim(),`.

5. Validation: when `_credentialLink` is non-empty, skip any required-apiKey validation (find the validator on the apiKey field / `_formInput` — linked rows are exempt).

- [ ] **Step 4: Run tests**

Run: `cd client && dart test test/widgets/app_provider/app_provider_form_credential_link_test.dart test/widgets/app_provider/app_provider_form_test.dart`
Expected: PASS all.

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/app_provider/app_provider_form_sheet.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/widgets/app_provider/app_provider_form_credential_link_test.dart
git commit -m "feat(providers): app provider form can reference a managed entry secret"
```

---

### Task 9: Full gate

**Files:**
- No new files. Fix anything the gate surfaces.

- [ ] **Step 1: Run the full verification gate**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
Expected: zero analyze errors, all tests pass. If l10n codegen is stale, run `flutter gen-l10n` first so generated localizations include the new keys.

- [ ] **Step 2: Fix any failures surfaced by the gate**

Common expected friction: generated `app_localizations*.dart` out of date (regenerate, do not hand-edit); editor schema tests asserting the old credentials-section layout; coordinator tests constructing `ManagedProviderCredentialResolver` with `const` (drop `const` at any remaining call sites).

- [ ] **Step 3: Commit any fixes and verify clean tree**

```bash
git status --short   # confirm no stray generated files staged
git add -A client/lib client/test
git commit -m "test(providers): full gate green for credential link feature"
```

(Skip the commit if the gate needed no fixes.)

---

## Self-Review Notes

- **Spec coverage**: credential forms (Task 1–2), forward resolution (Task 3), reverse resolution + materialization + credentialStatus (Task 4), cycle guard both directions (Task 5), deletion janitors (Task 6; provider-row deletion needs no code per spec), managed editor UI (Task 7), provider form UI (Task 8), full gate (Task 9). Scope restriction to apiKey-class is enforced by `requiresApiKey` filtering in Task 7 and category gating in Task 8.
- **Type consistency**: `managedProviderLinkSourceOf`/`managedProviderLinkSourceValue`/`ManagedProviderLinkSource` names are identical in Tasks 2–8; `credentialLink` field name identical in Tasks 1, 4–8; `LinkedCredentialLookup` defined once (Task 4).
- **Known simplification**: reverse-link liveness is per-load/per-save, not push-based — a rotated managed secret reaches native CLI config on the next provider save/load or session materialization (spec: "next read").
