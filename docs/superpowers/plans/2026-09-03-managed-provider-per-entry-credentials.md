# Managed Provider Per-Entry Official Credentials Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every managed-provider entry using a `cli:` credential source its own dedicated CLI provider row and isolated credential directory, remove global-home fallback in usage reads, and keep login / session launch / usage query pointed at the same isolated directory.

**Architecture:** A new `ManagedProviderCliBinding` service derives a per-entry CLI provider row id (`<cli>-mp-<managedProviderId>`), ensures the row exists in the CLI provider catalog, and rewrites the entry's `credentialSource` to `cli:<row-id>`. The three official-subscription auth readers read only the row's isolated directory (no global fallback). The editor login UI binds to the dedicated row via `AppProviderCubit.upsertProvider`.

**Tech Stack:** Flutter / Dart, flutter_bloc, in-repo `Filesystem` abstraction (`InMemoryFilesystem` in tests), no new packages.

**Spec:** `docs/superpowers/specs/2026-09-03-managed-provider-per-entry-credentials-design.md`

## Global Constraints

- All commands run from `/home/hhoa/git/hhoa/teampilot/client`.
- Test command: `dart run tool/run_tests.dart test/<path>.dart` (single file) or `flutter test test/<path>.dart` for plain `flutter_test` files. Before claiming done: `flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- ManagedProvider ids are generated in the editor as `managed-<epochMillis>` (`managed_provider_editor_page.dart:584`).
- CLI enum values (for directory naming): `claude`, `codex`, `cursor` (`CliTool.value` in `team_config.dart:21-26`). Use `cli.value` — never hardcode.
- Credential file names: claude `.credentials.json` directly under `providers/claude/<rowId>/`; codex `auth.json` under `providers/codex/<rowId>/`; cursor `auth.json` under `<home>/.config/cursor/auth.json` (Linux/Windows) or `<home>/.cursor/auth.json` (macOS) where `<home> = providers/cursor/<rowId>/home`.
- No new generic UI widgets; reuse `ProviderCredentialActionBar` unchanged.
- Never log or expose credential values; readers return `ProviderCredentialScope` whose `toString()` is redacted (already provided by `ManagedProviderAccessTokenScope`).
- Secret-free typed errors only: `ManagedProviderUsageQueryError(ManagedProviderUsageQueryErrorCode.missingCredential)`.

## Existing facts the implementer needs

- `OfficialManagedProviderBinding` (`client/lib/services/provider_usage/official_managed_provider_binding.dart`) currently maps `cli:cursor-account` / `cli:claude-official` / `cli:openai-official` to the shared rows. It stays (legacy rows remain launch-selectable), but the editor no longer uses it for new entries.
- CLI provider row templates live in `CursorProviderPresets.byId('cursor-account')` (`services/cli/cursor/provider_presets.dart`), `ClaudeProviderPresets.byId('claude-official')` (`services/cli/claude/provider_presets.dart`), `CodexProviderPresets.byId('openai-official')` (`services/cli/codex/provider_presets.dart`).
- `AppProviderCubit.upsertProvider(AppProviderConfig)` (cubits/app_provider_cubit.dart:298) persists a row via `AppProviderRepository.saveProviders`.
- The credential capability gates login buttons: cursor requires `cli == cursor && isOfficial` (`services/cli/cursor/capabilities/provider.dart:146`); claude requires `isOfficialClaudeProvider` (category official + official settings); codex requires `isOfficial && category == official`.
- `CliCredentialSourceResolver.read(source)` strips `cli:` and looks up `readers[<id>]`, passing a dummy `ManagedProvider(id: id, …)` to the reader (`cli_credential_source.dart:17-44`).
- The official readers today probe `providers/<cli>/<fixedId>/…` then fall back to `homeDirectory()` global paths.
- Editor save flow: `managed_provider_editor_page.dart` `_save()` at :563 computes `providerId = current?.id ?? 'managed-$now'`, builds `next` ManagedProvider, calls `cubit.upsert(next)`.
- Editor official credentials widget: `ManagedProviderOfficialCredentials(credentialSource: …)` at `managed_provider_editor_page.dart:234` — currently maps via `OfficialManagedProviderBinding.forCredentialSource` and ensures the fixed shared row.
- Test harness pattern for the editor page: `client/test/pages/managed_providers/managed_provider_management_page_test.dart` (cubits + `AppProviderCubit(repository: AppProviderRepository(fs: fs, basePath: '/tp'), basePath: '/tp')`, `applyPreset(tester, 'Cursor')` helper).
- Existing reader tests: `client/test/services/provider_usage/official_subscription_auth_test.dart` and `cli_credential_source_test.dart` — both currently assert the global fallback behavior and must be updated.

---

### Task 1: `ManagedProviderCliBinding` — per-entry row id + template derivation

**Files:**
- Create: `client/lib/services/provider_usage/managed_provider_cli_binding.dart`
- Test: `client/test/services/provider_usage/managed_provider_cli_binding_test.dart`

**Interfaces:**
- Consumes: `CliTool` (models/team_config.dart), `AppProviderConfig` (models/app_provider_config.dart), preset catalogs `CursorProviderPresets` / `ClaudeProviderPresets` / `CodexProviderPresets`.
- Produces (later tasks rely on these exact signatures):
  - `String managedProviderCliRowId(CliTool cli, String managedProviderId)` → `'<cli.value>-mp-<managedProviderId>'`
  - `class ManagedProviderCliBinding` with:
    - `const ManagedProviderCliBinding()`
    - `CliTool? cliForCredentialSource(String source)` — returns the CLI for `cli:<cli.value>-mp-*` **and** legacy `cli:cursor-account` / `cli:claude-official` / `cli:openai-official`; `null` otherwise
    - `bool isPerEntrySource(String source)` — true iff `cli:` source whose row id matches `<cli.value>-mp-*`
    - `String? rowIdForCredentialSource(String source)` — row id for per-entry sources; the legacy fixed id for legacy sources; `null` for non-`cli:` sources
    - `String? legacySourceForCli(CliTool cli)` — `'cli:cursor-account'` / `'cli:claude-official'` / `'cli:openai-official'` or `null`
    - `String? migrateCredentialSource(String source, CliTool? Function(String rowId) rowExists)` — for a legacy source, returns `'cli:<cli.value>-mp-<rowId-for-entry>'` given the managed provider id embedded... (see step 3 for the actual simpler signature: `String? migrateCredentialSource({required String source, required String managedProviderId})`)
    - `AppProviderConfig? rowTemplateFor(CliTool cli, String managedProviderId, String managedProviderName)` — preset template copied with new id and name `<PresetName> (<managedProviderName>)`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/provider_usage/managed_provider_cli_binding.dart';

void main() {
  const binding = ManagedProviderCliBinding();

  test('row id is cli-mp-providerId', () {
    expect(
      managedProviderCliRowId(CliTool.cursor, 'managed-123'),
      'cursor-mp-managed-123',
    );
    expect(
      managedProviderCliRowId(CliTool.claude, 'managed-123'),
      'claude-mp-managed-123',
    );
    expect(
      managedProviderCliRowId(CliTool.codex, 'managed-123'),
      'codex-mp-managed-123',
    );
  });

  test('cliForCredentialSource recognizes per-entry and legacy sources', () {
    expect(
      binding.cliForCredentialSource('cli:cursor-mp-managed-1'),
      CliTool.cursor,
    );
    expect(binding.cliForCredentialSource('cli:claude-mp-m-1'), CliTool.claude);
    expect(binding.cliForCredentialSource('cli:codex-mp-m-1'), CliTool.codex);
    expect(binding.cliForCredentialSource('cli:cursor-account'), CliTool.cursor);
    expect(binding.cliForCredentialSource('cli:claude-official'), CliTool.claude);
    expect(binding.cliForCredentialSource('cli:openai-official'), CliTool.codex);
    expect(binding.cliForCredentialSource('secret'), isNull);
    expect(binding.cliForCredentialSource('cli:nope'), isNull);
    expect(binding.cliForCredentialSource('cli:cursor-mp-'), isNull);
  });

  test('isPerEntrySource distinguishes per-entry from legacy', () {
    expect(binding.isPerEntrySource('cli:cursor-mp-managed-1'), isTrue);
    expect(binding.isPerEntrySource('cli:cursor-account'), isFalse);
    expect(binding.isPerEntrySource('secret'), isFalse);
  });

  test('rowIdForCredentialSource extracts row id', () {
    expect(
      binding.rowIdForCredentialSource('cli:cursor-mp-managed-1'),
      'cursor-mp-managed-1',
    );
    expect(
      binding.rowIdForCredentialSource('cli:cursor-account'),
      'cursor-account',
    );
    expect(binding.rowIdForCredentialSource('secret'), isNull);
  });

  test('migrateCredentialSource rewrites legacy to per-entry', () {
    expect(
      binding.migrateCredentialSource(
        source: 'cli:cursor-account',
        managedProviderId: 'managed-9',
      ),
      'cli:cursor-mp-managed-9',
    );
    expect(
      binding.migrateCredentialSource(
        source: 'cli:claude-official',
        managedProviderId: 'managed-9',
      ),
      'cli:claude-mp-managed-9',
    );
    expect(
      binding.migrateCredentialSource(
        source: 'cli:openai-official',
        managedProviderId: 'managed-9',
      ),
      'cli:codex-mp-managed-9',
    );
    expect(
      binding.migrateCredentialSource(
        source: 'cli:cursor-mp-managed-9',
        managedProviderId: 'managed-9',
      ),
      isNull,
    );
    expect(
      binding.migrateCredentialSource(
        source: 'secret',
        managedProviderId: 'managed-9',
      ),
      isNull,
    );
  });

  test('rowTemplateFor derives dedicated row from official preset', () {
    final template = binding.rowTemplateFor(
      CliTool.cursor,
      'managed-1',
      'My Cursor',
    );
    expect(template?.id, 'cursor-mp-managed-1');
    expect(template?.cli, CliTool.cursor);
    expect(template?.name, 'Cursor Account (My Cursor)');
    expect(template?.isOfficial, isTrue);
    expect(template?.category, AppProviderCategory.official);

    final claude = binding.rowTemplateFor(CliTool.claude, 'm1', 'Work');
    expect(claude?.id, 'claude-mp-m1');
    expect(claude?.isOfficial, isTrue);
    expect(claude?.category, AppProviderCategory.official);

    final codex = binding.rowTemplateFor(CliTool.codex, 'm1', 'Work');
    expect(codex?.id, 'codex-mp-m1');
    expect(codex?.isOfficial, isTrue);
    expect(codex?.category, AppProviderCategory.official);

    expect(binding.rowTemplateFor(CliTool.opencode, 'm1', 'X'), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/provider_usage/managed_provider_cli_binding_test.dart`
Expected: FAIL — `managed_provider_cli_binding.dart` does not exist (import error).

- [ ] **Step 3: Write minimal implementation**

```dart
import '../../models/app_provider_config.dart';
import '../../models/team_config.dart';
import '../cli/claude/provider_presets.dart';
import '../cli/codex/provider_presets.dart';
import '../cli/cursor/provider_presets.dart';

/// Per-entry CLI provider row binding for managed-provider `cli:` sources.
///
/// A managed-provider entry that uses an official CLI credential source owns
/// a dedicated CLI provider row (`<cli>-mp-<managedProviderId>`) whose
/// isolated HOME holds that entry's login. Legacy shared sources
/// (`cli:cursor-account`, `cli:claude-official`, `cli:openai-official`) are
/// recognized and migrated to per-entry sources.
class ManagedProviderCliBinding {
  const ManagedProviderCliBinding();

  static const _legacyByCli = <CliTool, String>{
    CliTool.cursor: 'cursor-account',
    CliTool.claude: 'claude-official',
    CliTool.codex: 'openai-official',
  };

  static const _legacyTemplates = <CliTool, AppProviderConfig Function()>{
    CliTool.cursor: _cursorTemplate,
    CliTool.claude: _claudeTemplate,
    CliTool.codex: _codexTemplate,
  };

  static AppProviderConfig _cursorTemplate() =>
      CursorProviderPresets.byId('cursor-account')!.template;

  static AppProviderConfig _claudeTemplate() =>
      ClaudeProviderPresets.byId('claude-official')!.template;

  static AppProviderConfig _codexTemplate() =>
      CodexProviderPresets.byId('openai-official')!.template;

  CliTool? cliForCredentialSource(String source) {
    final rowId = rowIdForCredentialSource(source);
    if (rowId == null) return null;
    for (final cli in _legacyByCli.keys) {
      if (rowId.startsWith('${cli.value}-mp-')) return cli;
      if (_legacyByCli[cli] == rowId) return cli;
    }
    return null;
  }

  bool isPerEntrySource(String source) =>
      cliForCredentialSource(source) != null &&
      (rowIdForCredentialSource(source) ?? '').contains('-mp-');

  String? rowIdForCredentialSource(String source) {
    const prefix = 'cli:';
    if (!source.startsWith(prefix)) return null;
    final rowId = source.substring(prefix.length).trim();
    return rowId.isEmpty ? null : rowId;
  }

  String? legacySourceForCli(CliTool cli) {
    final rowId = _legacyByCli[cli];
    return rowId == null ? null : 'cli:$rowId';
  }

  /// Rewrites a legacy shared source to the entry's per-entry source, or
  /// `null` when [source] is already per-entry, non-`cli:`, or unknown.
  String? migrateCredentialSource({
    required String source,
    required String managedProviderId,
  }) {
    final cli = cliForCredentialSource(source);
    if (cli == null || isPerEntrySource(source)) return null;
    if (rowIdForCredentialSource(source) != _legacyByCli[cli]) return null;
    return 'cli:${managedProviderCliRowId(cli, managedProviderId)}';
  }

  /// Dedicated CLI provider row for a managed-provider entry, or `null` for
  /// CLIs without an official preset.
  AppProviderConfig? rowTemplateFor(
    CliTool cli,
    String managedProviderId,
    String managedProviderName,
  ) {
    final factory_ = _legacyTemplates[cli];
    if (factory_ == null) return null;
    final preset = factory_();
    return preset.copyWith(
      id: managedProviderCliRowId(cli, managedProviderId),
      name: '${preset.name} ($managedProviderName)',
    );
  }
}

String managedProviderCliRowId(CliTool cli, String managedProviderId) =>
    '${cli.value}-mp-${managedProviderId.trim()}';
```

Note: `_legacyByCli.keys` iteration order is insertion order (claude, codex, cursor); the `-mp-` prefix check is per-CLI so `cursor-mp-x` matches cursor and `claude-mp-x` matches claude — a row id like `claude-mp-…` can only start with one CLI's `value`. Verify with the test: `cliForCredentialSource('cli:cursor-mp-')` returns null because the row id `cursor-mp-` has an empty trailing provider id segment — handle by also requiring the `-mp-` suffix part (or bare legacy ids) to be non-empty. If the test `'cli:cursor-mp-'` case fails, guard with: `if (rowId.endsWith('-mp-') || rowId.endsWith('-mp')) return null;` inside the loop before the prefix check.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/provider_usage/managed_provider_cli_binding_test.dart`
Expected: PASS (all 6 tests).

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/provider_usage/managed_provider_cli_binding.dart client/test/services/provider_usage/managed_provider_cli_binding_test.dart
git commit -m "Add ManagedProviderCliBinding for per-entry CLI provider rows"
```

---

### Task 2: Readers read only the isolated per-entry directory (no global fallback)

**Files:**
- Modify: `client/lib/services/provider_usage/adapters/cursor_official_subscription_auth.dart` (whole `read()` rewrite)
- Modify: `client/lib/services/provider_usage/adapters/claude_official_subscription_auth.dart` (whole `read()` rewrite)
- Modify: `client/lib/services/provider_usage/adapters/codex_official_subscription_auth.dart` (whole `read()` rewrite)
- Test: `client/test/services/provider_usage/official_subscription_auth_test.dart` (rewrite tests)

**Interfaces:**
- Consumes: `readOfficialCredentialJson` / `missingOfficialCredential` / `ManagedProviderAccessTokenScope` from `official_credential_files.dart`; `CursorHomeLayout` from `services/cli/cursor/provider/cursor_home_layout.dart`.
- Produces (unchanged public API, changed semantics): each `read(ManagedProvider provider)` now resolves the row id from the source string via a new constructor param `String Function(String source)? sourceForRowId` — **simpler**: readers keep taking `fs`, `basePath`, `homeDirectory` (homeDirectory param becomes unused and is removed from constructors), and `CliCredentialSourceResolver` passes the row id through the dummy provider's `provider.id`. The reader derives the isolated directory from `provider.id`:
  - cursor: `<basePath>/providers/cursor/<provider.id>/home`
  - claude: `<basePath>/providers/claude/<provider.id>/.credentials.json`
  - codex: `<basePath>/providers/codex/<provider.id>/auth.json`
- `CliCredentialSourceResolver.read()` (Task 2 modifies `cli_credential_source.dart`) already builds the dummy provider with `id: <source-minus-cli:>` — so the reader receives the row id as `provider.id`. No change needed in `cli_credential_source.dart`.

- [ ] **Step 1: Write the failing tests (rewrite the existing test file)**

Replace the contents of `client/test/services/provider_usage/official_subscription_auth_test.dart` with:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/services/provider_usage/adapters/claude_official_subscription_auth.dart';
import 'package:teampilot/services/provider_usage/adapters/codex_official_subscription_auth.dart';
import 'package:teampilot/services/provider_usage/adapters/cursor_official_subscription_auth.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_layout.dart';
import 'package:teampilot/services/provider_usage/cli_credential_source.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';

import '../../support/in_memory_filesystem.dart';

ManagedProvider _provider(String rowId) => ManagedProvider(
  id: rowId,
  name: 'Official',
  kind: ManagedProviderKind.subscriptionQuota,
  adapterId: 'http-json',
);

void main() {
  late InMemoryFilesystem fs;
  late CursorHomeLayout layout;

  setUp(() {
    fs = InMemoryFilesystem();
    layout = CursorHomeLayout(pathContext: fs.pathContext);
  });

  test('Claude auth reads only the per-entry isolated credential file', () async {
    await fs.writeString(
      '/tp/providers/claude/claude-mp-managed-1/.credentials.json',
      jsonEncode({
        'claudeAiOauth': {'accessToken': 'per-entry-token'},
      }),
    );
    await fs.writeString(
      '/home/.claude/.credentials.json',
      jsonEncode({
        'claudeAiOauth': {'accessToken': 'global-token'},
      }),
    );

    final scope = await ClaudeOfficialSubscriptionAuthReader(
      fs: fs,
      basePath: '/tp',
    ).read(_provider('claude-mp-managed-1'));

    expect(scope?.valueFor('accessToken'), 'per-entry-token');
    expect(scope.toString(), isNot(contains('per-entry-token')));
  });

  test('Claude auth never falls back to ~/.claude credentials', () async {
    await fs.writeString(
      '/home/.claude/.credentials.json',
      jsonEncode({
        'claudeAiOauth': {'accessToken': 'global-token'},
      }),
    );

    await expectLater(
      ClaudeOfficialSubscriptionAuthReader(fs: fs, basePath: '/tp')
          .read(_provider('claude-mp-managed-1')),
      throwsA(
        isA<ManagedProviderUsageQueryError>().having(
          (error) => error.code,
          'code',
          ManagedProviderUsageQueryErrorCode.missingCredential,
        ),
      ),
    );
  });

  test('Codex auth reads only the per-entry isolated auth.json', () async {
    await fs.writeString(
      '/tp/providers/codex/codex-mp-managed-1/auth.json',
      jsonEncode({
        'auth_mode': 'chatgpt',
        'tokens': {'access_token': 'per-entry', 'account_id': 'acct-1'},
      }),
    );
    await fs.writeString(
      '/home/.codex/auth.json',
      jsonEncode({
        'auth_mode': 'chatgpt',
        'tokens': {'access_token': 'global', 'account_id': 'acct-g'},
      }),
    );

    final scope = await CodexOfficialSubscriptionAuthReader(
      fs: fs,
      basePath: '/tp',
    ).read(_provider('codex-mp-managed-1'));

    expect(scope?.valueFor('accessToken'), 'per-entry');
    expect(scope?.valueFor('accountId'), 'acct-1');
  });

  test('Codex auth never falls back to ~/.codex and skips apikey mode',
      () async {
    await fs.writeString(
      '/home/.codex/auth.json',
      jsonEncode({
        'auth_mode': 'apikey',
        'tokens': {'access_token': 'api-mode'},
      }),
    );

    await expectLater(
      CodexOfficialSubscriptionAuthReader(fs: fs, basePath: '/tp')
          .read(_provider('codex-mp-managed-1')),
      throwsA(
        isA<ManagedProviderUsageQueryError>().having(
          (error) => error.code,
          'code',
          ManagedProviderUsageQueryErrorCode.missingCredential,
        ),
      ),
    );
  });

  test('Cursor auth reads only the per-entry isolated auth.json', () async {
    final home = '/tp/providers/cursor/cursor-mp-managed-1/home';
    await fs.writeString(
      layout.authJson(home),
      jsonEncode({'accessToken': 'per-entry-cursor', 'userId': 'user-1'}),
    );
    // Global IDE login exists — must be ignored.
    await fs.writeString(
      layout.authJson('/home'),
      jsonEncode({'accessToken': 'global-cursor'}),
    );

    final scope = await CursorOfficialSubscriptionAuthReader(
      fs: fs,
      basePath: '/tp',
    ).read(_provider('cursor-mp-managed-1'));

    expect(scope?.valueFor('accessToken'), 'per-entry-cursor');
    expect(scope?.valueFor('accountId'), 'user-1');
  });

  test('Cursor auth never falls back to global cursor auth.json', () async {
    await fs.writeString(
      layout.authJson('/home'),
      jsonEncode({'accessToken': 'global-cursor'}),
    );

    await expectLater(
      CursorOfficialSubscriptionAuthReader(fs: fs, basePath: '/tp')
          .read(_provider('cursor-mp-managed-1')),
      throwsA(
        isA<ManagedProviderUsageQueryError>().having(
          (error) => error.code,
          'code',
          ManagedProviderUsageQueryErrorCode.missingCredential,
        ),
      ),
    );
  });

  test('Legacy shared rows still resolve through the isolated directory',
      () async {
    await fs.writeString(
      '/tp/providers/claude/claude-official/.credentials.json',
      jsonEncode({
        'claudeAiOauth': {'accessToken': 'legacy-row-token'},
      }),
    );

    final scope = await ClaudeOfficialSubscriptionAuthReader(
      fs: fs,
      basePath: '/tp',
    ).read(_provider('claude-official'));

    expect(scope?.valueFor('accessToken'), 'legacy-row-token');
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/provider_usage/official_subscription_auth_test.dart`
Expected: FAIL — constructors still require `homeDirectory:`; fallback tests fail because readers still read global paths.

- [ ] **Step 3: Rewrite the three readers**

`claude_official_subscription_auth.dart` — replace the class body:

```dart
import '../../../models/managed_provider.dart';
import '../../io/filesystem.dart';
import 'official_credential_files.dart';
import 'cli_credential_source.dart';

class ClaudeOfficialSubscriptionAuthReader
    implements OfficialSubscriptionAuthReader {
  ClaudeOfficialSubscriptionAuthReader({
    required Filesystem fs,
    required String basePath,
  }) : _fs = fs,
       _basePath = basePath;

  final Filesystem _fs;
  final String _basePath;

  @override
  Future<ProviderCredentialScope?> read(ManagedProvider provider) async {
    final path = _fs.pathContext.join(
      _basePath,
      'providers',
      'claude',
      provider.id.trim(),
      '.credentials.json',
    );
    final json = await readOfficialCredentialJson(_fs, path);
    final token = _claudeAccessToken(json);
    if (token != null) {
      return ManagedProviderAccessTokenScope(accessToken: token);
    }
    missingOfficialCredential();
  }

  String? _claudeAccessToken(Map<String, Object?>? json) {
    final oauth = json?['claudeAiOauth'];
    if (oauth is! Map) return null;
    final token = '${oauth['accessToken'] ?? ''}'.trim();
    return token.isEmpty ? null : token;
  }
}
```

`codex_official_subscription_auth.dart` — same pattern:

```dart
import '../../../models/managed_provider.dart';
import '../../io/filesystem.dart';
import 'official_credential_files.dart';
import '../cli_credential_source.dart';

class CodexOfficialSubscriptionAuthReader
    implements OfficialSubscriptionAuthReader {
  CodexOfficialSubscriptionAuthReader({
    required Filesystem fs,
    required String basePath,
  }) : _fs = fs,
       _basePath = basePath;

  final Filesystem _fs;
  final String _basePath;

  @override
  Future<ProviderCredentialScope?> read(ManagedProvider provider) async {
    final path = _fs.pathContext.join(
      _basePath,
      'providers',
      'codex',
      provider.id.trim(),
      'auth.json',
    );
    final json = await readOfficialCredentialJson(_fs, path);
    final tokens = _codexTokens(json);
    if (tokens != null) {
      return ManagedProviderAccessTokenScope(
        accessToken: tokens.accessToken,
        accountId: tokens.accountId,
      );
    }
    missingOfficialCredential();
  }

  ({String accessToken, String? accountId})? _codexTokens(
    Map<String, Object?>? json,
  ) {
    if (json == null) return null;
    final mode = json['auth_mode']?.toString().trim();
    if (mode != null && mode.isNotEmpty && mode != 'chatgpt') return null;
    final rawTokens = json['tokens'];
    final tokens = rawTokens is Map
        ? rawTokens.map((key, value) => MapEntry(key.toString(), value))
        : const <String, Object?>{};
    final access = '${tokens['access_token'] ?? json['access_token'] ?? ''}'
        .trim();
    if (access.isEmpty) return null;
    final account = '${tokens['account_id'] ?? json['account_id'] ?? ''}'
        .trim();
    return (accessToken: access, accountId: account.isEmpty ? null : account);
  }
}
```

`cursor_official_subscription_auth.dart`:

```dart
import '../../../models/managed_provider.dart';
import '../../cli/cursor/provider/cursor_home_layout.dart';
import '../../io/filesystem.dart';
import '../cli_credential_source.dart';
import 'official_credential_files.dart';

class CursorOfficialSubscriptionAuthReader
    implements OfficialSubscriptionAuthReader {
  CursorOfficialSubscriptionAuthReader({
    required Filesystem fs,
    required String basePath,
    CursorHomeLayout? layout,
  }) : _fs = fs,
       _basePath = basePath,
       _layout = layout ?? CursorHomeLayout(pathContext: fs.pathContext);

  final Filesystem _fs;
  final String _basePath;
  final CursorHomeLayout _layout;

  @override
  Future<ProviderCredentialScope?> read(ManagedProvider provider) async {
    final isolatedHome = _fs.pathContext.join(
      _basePath,
      'providers',
      'cursor',
      provider.id.trim(),
      'home',
    );
    for (final authPath in _layout.authJsonCandidates(isolatedHome)) {
      final tokens = await _cursorTokens(authPath, isolatedHome);
      if (tokens != null) {
        return ManagedProviderAccessTokenScope(
          accessToken: tokens.accessToken,
          accountId: tokens.userId,
        );
      }
    }
    missingOfficialCredential();
  }

  Future<({String accessToken, String? userId})?> _cursorTokens(
    String authPath,
    String home,
  ) async {
    final json = await readOfficialCredentialJson(_fs, authPath);
    final access = '${json?['accessToken'] ?? ''}'.trim();
    if (access.isEmpty) return null;
    final fromAuth = '${json?['userId'] ?? ''}'.trim();
    if (fromAuth.isNotEmpty) {
      return (accessToken: access, userId: fromAuth);
    }
    final cliConfig = await readOfficialCredentialJson(
      _fs,
      _layout.cliConfig(home),
    );
    final authInfo = cliConfig?['authInfo'];
    final fromCli = authInfo is Map ? '${authInfo['userId'] ?? ''}'.trim() : '';
    return (
      accessToken: access,
      userId: fromCli.isEmpty ? null : fromCli,
    );
  }
}
```

Then update all construction sites that passed `homeDirectory:`:
- `client/lib/app/app_shell.dart:914-928` — remove the `homeDirectory: () => AppStorage.home,` lines from the three readers.
- `client/test/services/provider_usage/cli_credential_source_test.dart` — remove `homeDirectory: () => '/home'`.
- `client/test/app/app_shell_provider_usage_bootstrap_test.dart:83` — remove `homeDirectory:` line.
- Grep check: `grep -rn "OfficialSubscriptionAuthReader(" client/lib client/test` — no construction site still passes `homeDirectory`.

- [ ] **Step 4: Run reader + related tests**

Run: `flutter test test/services/provider_usage/official_subscription_auth_test.dart test/services/provider_usage/cli_credential_source_test.dart test/app/app_shell_provider_usage_bootstrap_test.dart`
Expected: PASS. (`cli_credential_source_test.dart` "prefers isolated auth.json" still passes — the reader reads `providers/cursor/cursor-account/home` via `provider.id == 'cursor-account'`.)

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/provider_usage/adapters/ client/lib/app/app_shell.dart client/test/services/provider_usage/official_subscription_auth_test.dart client/test/services/provider_usage/cli_credential_source_test.dart client/test/app/app_shell_provider_usage_bootstrap_test.dart
git commit -m "Read official CLI credentials only from per-entry isolated directories"
```

---

### Task 3: Resolver routes per-entry sources to per-CLI readers

**Files:**
- Modify: `client/lib/services/provider_usage/cli_credential_source.dart`
- Modify: `client/lib/app/app_shell.dart:912-930` (reader registry wiring)
- Test: `client/test/services/provider_usage/cli_credential_source_test.dart` (extend)

**Interfaces:**
- Consumes: `ManagedProviderCliBinding.cliForCredentialSource` / `rowIdForCredentialSource` (Task 1), the three readers (Task 2).
- Produces: `CliCredentialSourceResolver` whose reader registry is keyed by CLI value (`claude`, `codex`, `cursor`) and whose `read(source)` accepts **any** `cli:<rowId>` source whose CLI has a reader — resolution is by CLI, not by fixed row id. `app_shell.dart` wires three readers keyed `'claude'` / `'codex'` / `'cursor'`.

- [ ] **Step 1: Write the failing tests (extend the existing file)**

Add to `client/test/services/provider_usage/cli_credential_source_test.dart` inside `main()`:

```dart
  test('per-entry cursor source resolves through the cursor reader',
      () async {
    final fs = InMemoryFilesystem();
    final layout = CursorHomeLayout(pathContext: fs.pathContext);
    await fs.writeString(
      layout.authJson('/tp/providers/cursor/cursor-mp-managed-7/home'),
      jsonEncode({'accessToken': 'entry-token'}),
    );
    final scope = await CliCredentialSourceResolver(
      readers: {
        'cursor': CursorOfficialSubscriptionAuthReader(
          fs: fs,
          basePath: '/tp',
        ),
      },
    ).read('cli:cursor-mp-managed-7');
    expect(scope.valueFor('accessToken'), 'entry-token');
  });

  test('per-entry claude source resolves through the claude reader',
      () async {
    final fs = InMemoryFilesystem();
    await fs.writeString(
      '/tp/providers/claude/claude-mp-managed-7/.credentials.json',
      jsonEncode({
        'claudeAiOauth': {'accessToken': 'entry-token'},
      }),
    );
    final scope = await CliCredentialSourceResolver(
      readers: {
        'claude': ClaudeOfficialSubscriptionAuthReader(
          fs: fs,
          basePath: '/tp',
        ),
      },
    ).read('cli:claude-mp-managed-7');
    expect(scope.valueFor('accessToken'), 'entry-token');
  });

  test('legacy cursor-account source resolves through the cursor reader',
      () async {
    final fs = InMemoryFilesystem();
    final layout = CursorHomeLayout(pathContext: fs.pathContext);
    await fs.writeString(
      layout.authJson('/tp/providers/cursor/cursor-account/home'),
      jsonEncode({'accessToken': 'legacy-token'}),
    );
    final scope = await CliCredentialSourceResolver(
      readers: {
        'cursor': CursorOfficialSubscriptionAuthReader(
          fs: fs,
          basePath: '/tp',
        ),
      },
    ).read('cli:cursor-account');
    expect(scope.valueFor('accessToken'), 'legacy-token');
  });

  test('unmapped cli still reports missingCredential', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString(
      '/tp/providers/claude/claude-mp-x/.credentials.json',
      jsonEncode({
        'claudeAiOauth': {'accessToken': 't'},
      }),
    );
    await expectLater(
      CliCredentialSourceResolver(
        readers: {
          'cursor': CursorOfficialSubscriptionAuthReader(
            fs: fs,
            basePath: '/tp',
          ),
        },
      ).read('cli:claude-mp-x'),
      throwsA(isA<ManagedProviderUsageQueryError>().having(
        (e) => e.code,
        'code',
        ManagedProviderUsageQueryErrorCode.missingCredential,
      )),
    );
  });
```

Also update the file's first test (`'cli:cursor-account prefers isolated auth.json'`): change its readers key from `'cursor-account'` to `'cursor'`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/provider_usage/cli_credential_source_test.dart`
Expected: FAIL — resolver looks up `readers[<rowId>]`, not `readers[<cli>]`.

- [ ] **Step 3: Update the resolver**

Replace `read()` in `client/lib/services/provider_usage/cli_credential_source.dart`:

```dart
  Future<ProviderCredentialScope> read(String source) async {
    const prefix = 'cli:';
    if (!source.startsWith(prefix)) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
    final rowId = source.substring(prefix.length).trim();
    if (rowId.isEmpty) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
    // Readers are keyed by CLI value; any row id (per-entry or legacy)
    // resolves through its CLI's reader, which reads the isolated
    // `providers/<cli>/<rowId>/` directory.
    final cli = ManagedProviderCliBinding().cliForCredentialSource(source);
    final reader = cli == null ? null : readers[cli.value];
    if (reader == null) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
    final dummy = ManagedProvider(
      id: rowId,
      name: rowId,
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
```

Add import at top: `import 'managed_provider_cli_binding.dart';`

Update `client/lib/app/app_shell.dart:912-930` reader keys:

```dart
            CliCredentialSourceResolver(
              readers: {
                'claude': ClaudeOfficialSubscriptionAuthReader(
                  fs: AppStorage.fs,
                  basePath: AppStorage.paths.basePath,
                ),
                'codex': CodexOfficialSubscriptionAuthReader(
                  fs: AppStorage.fs,
                  basePath: AppStorage.paths.basePath,
                ),
                'cursor': CursorOfficialSubscriptionAuthReader(
                  fs: AppStorage.fs,
                  basePath: AppStorage.paths.basePath,
                ),
              },
            ),
```

Update `client/test/app/app_shell_provider_usage_bootstrap_test.dart:83` key `'claude-official'` → `'claude'` (and its fetch's `credentialSource: 'cli:claude-official'` stays — it must still resolve via the CLI-keyed reader; verify the isolated write path in that test writes to `/tp/providers/claude/claude-official/.credentials.json`; if it wrote a global path it must be updated to the isolated path).

- [ ] **Step 4: Run tests**

Run: `flutter test test/services/provider_usage/cli_credential_source_test.dart test/app/app_shell_provider_usage_bootstrap_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/provider_usage/cli_credential_source.dart client/lib/app/app_shell.dart client/test/services/provider_usage/cli_credential_source_test.dart client/test/app/app_shell_provider_usage_bootstrap_test.dart
git commit -m "Route cli: credential sources through per-CLI readers"
```

---

### Task 4: Ensure + migrate dedicated rows in `ManagedProviderCubit.load/upsert`

**Files:**
- Modify: `client/lib/cubits/managed_provider_cubit.dart`
- Test: `client/test/cubits/managed_provider_cubit_cli_binding_test.dart` (new)

**Interfaces:**
- Consumes: `ManagedProviderCliBinding` (Task 1), `AppProviderCubit.upsertProvider` (existing), `AppProviderRepository` (existing).
- Produces: `ManagedProviderCubit` gains a constructor param `AppProviderCubit? appProviderCubit` and an injected `ManagedProviderCliBinding binding` (defaults to `const ManagedProviderCliBinding()`):
  - On `upsert(provider)`: if `provider.endpointConfig.credentialSource` is a legacy `cli:` source, rewrite it to the per-entry source (`cli:<cli>-mp-<provider.id>`) before persisting; then ensure the dedicated CLI row exists via `appProviderCubit.upsertProvider(template)` when the row is absent from `appProviderCubit.state.providersFor(cli)`. If `appProviderCubit` is null, skip row ensuring (tests / legacy wiring) but still rewrite the source.
  - On `_loadInternal()`: for each loaded provider with a legacy source, rewrite source + ensure row (migration). Idempotent: per-entry sources are skipped.
- `app_shell.dart:948-962` passes `appProviderCubit` into `ManagedProviderCubit(...)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/managed_provider_cubit.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/models/team_config.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late ManagedProviderRepository repo;
  late ManagedProviderUsageRepositoryStub usageRepo;

  setUp(() {
    fs = InMemoryFilesystem();
    repo = ManagedProviderRepository(
      fs: fs,
      configPath: '/tp/managed-providers.json',
      onProvidersDeleted: usageRepoStub,
    );
  });

  // Minimal stub matching ManagedProviderUsageRepository.deleteMany.
  final usageRepoStub = _UsageRepoStub();
  class _UsageRepoStub {
    Future<void> deleteMany(List<String> ids) async {}
  }

  ManagedProvider _entry({
    required String id,
    String source = 'cli:cursor-account',
  }) => ManagedProvider(
    id: id,
    name: 'Cursor Usage',
    kind: ManagedProviderKind.subscriptionQuota,
    adapterId: 'http-json',
    endpointConfig: ManagedProviderEndpointConfig(
      url: 'https://cursor.com/api/usage-summary',
      credentialSource: source,
      credentialName: 'Cookie',
      credentialTemplate: 'WorkosCursorSessionToken={accountId}::{accessToken}',
    ),
  );

  test('upsert rewrites legacy source to per-entry source', () async {
    final appCubit = AppProviderCubit(
      repository: AppProviderRepository(fs: fs, basePath: '/tp'),
      basePath: '/tp',
    );
    final cubit = ManagedProviderCubit(
      repository: repo,
      appProviderCubit: appCubit,
    );

    await cubit.upsert(_entry(id: 'managed-1'));

    final saved = cubit.state.providerFor('managed-1')!;
    expect(
      saved.endpointConfig.credentialSource,
      'cli:cursor-mp-managed-1',
    );
    final cursorRows = appCubit.state.providersFor(CliTool.cursor);
    expect(
      cursorRows.any((row) => row.id == 'cursor-mp-managed-1'),
      isTrue,
    );
    await cubit.close();
    await appCubit.close();
  });

  test('upsert is idempotent for already per-entry sources', () async {
    await repo.save([_entry(id: 'managed-2', source: 'cli:cursor-mp-managed-2')]);
    final appCubit = AppProviderCubit(
      repository: AppProviderRepository(fs: fs, basePath: '/tp'),
      basePath: '/tp',
    );
    final cubit = ManagedProviderCubit(
      repository: repo,
      appProviderCubit: appCubit,
    );
    await cubit.load();

    final loaded = cubit.state.providerFor('managed-2')!;
    expect(
      loaded.endpointConfig.credentialSource,
      'cli:cursor-mp-managed-2',
    );
    await cubit.close();
    await appCubit.close();
  });

  test('load migrates legacy source entries and ensures rows', () async {
    await repo.save([_entry(id: 'managed-3')]);
    final appCubit = AppProviderCubit(
      repository: AppProviderRepository(fs: fs, basePath: '/tp'),
      basePath: '/tp',
    );
    final cubit = ManagedProviderCubit(
      repository: repo,
      appProviderCubit: appCubit,
    );
    await cubit.load();

    final migrated = cubit.state.providerFor('managed-3')!;
    expect(
      migrated.endpointConfig.credentialSource,
      'cli:cursor-mp-managed-3',
    );
    final persisted = await repo.load();
    expect(
      persisted.first.endpointConfig.credentialSource,
      'cli:cursor-mp-managed-3',
    );
    expect(
      appCubit.state.providersFor(CliTool.cursor)
          .any((row) => row.id == 'cursor-mp-managed-3'),
      isTrue,
    );
    await cubit.close();
    await appCubit.close();
  });
}
```

(Note: the `_UsageRepoStub` class above must be hoisted outside `main()` — Dart does not allow local classes referenced by a field initializer. Place the class at file bottom and declare `late final _UsageRepoStub usageRepoStub = _UsageRepoStub();` used by `setUp`. Fix while writing.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/cubits/managed_provider_cubit_cli_binding_test.dart`
Expected: FAIL — `ManagedProviderCubit` has no `appProviderCubit` param; sources are not rewritten.

- [ ] **Step 3: Implement in the cubit**

In `client/lib/cubits/managed_provider_cubit.dart`:

1. Add imports:

```dart
import '../models/team_config.dart';
import '../services/provider_usage/managed_provider_cli_binding.dart';
import 'app_provider_cubit.dart';
```

2. Extend the constructor:

```dart
  ManagedProviderCubit({
    required ManagedProviderRepository repository,
    Future<void> Function(String providerId)? onProviderDeletedState,
    Future<void> Function(ManagedProvider provider)?
    onProviderDeletedCredentialCleanup,
    AppProviderCubit? appProviderCubit,
    ManagedProviderCliBinding binding =
        const ManagedProviderCliBinding(),
  }) : _repository = repository,
       _onProviderDeletedState = onProviderDeletedState,
       _onProviderDeletedCredentialCleanup = onProviderDeletedCredentialCleanup,
       _appProviderCubit = appProviderCubit,
       _binding = binding,
       super(ManagedProviderState());

  final AppProviderCubit? _appProviderCubit;
  final ManagedProviderCliBinding _binding;
```

3. Add the ensure/migrate helpers:

```dart
  /// Rewrites legacy `cli:` sources to the per-entry source and ensures the
  /// dedicated CLI provider row exists. Returns the (possibly rewritten)
  /// provider.
  Future<ManagedProvider> _ensurePerEntryBinding(
    ManagedProvider provider,
  ) async {
    final source = provider.endpointConfig.credentialSource.trim();
    final next = _binding.migrateCredentialSource(
      source: source,
      managedProviderId: provider.id,
    );
    final provider0 = next == null
        ? provider
        : provider.copyWith(
            endpointConfig: provider.endpointConfig.copyWith(
              credentialSource: next,
            ),
          );
    await _ensureCliRow(provider0);
    return provider0;
  }

  Future<void> _ensureCliRow(ManagedProvider provider) async {
    final appCubit = _appProviderCubit;
    if (appCubit == null) return;
    final source = provider.endpointConfig.credentialSource.trim();
    final cli = _binding.cliForCredentialSource(source);
    if (cli == null) return;
    final rowId = _binding.rowIdForCredentialSource(source);
    if (rowId == null) return;
    final existing = appCubit.state
        .providersFor(cli)
        .where((row) => row.id == rowId)
        .firstOrNull;
    if (existing != null) return;
    final template = _binding.rowTemplateFor(cli, provider.id, provider.name);
    if (template == null) return;
    await appCubit.upsertProvider(template);
  }
```

Note: `ManagedProviderEndpointConfig` has no `copyWith` — construct a new one in the rewrite instead. Check `client/lib/models/managed_provider.dart:124-155`: the public `factory ManagedProviderEndpointConfig({...})` takes all fields. Use:

```dart
    final provider0 = next == null
        ? provider
        : provider.copyWith(
            endpointConfig: ManagedProviderEndpointConfig(
              url: provider.endpointConfig.url,
              method: provider.endpointConfig.method,
              responsePath: provider.endpointConfig.responsePath,
              credentialField: provider.endpointConfig.credentialField,
              credentialName: provider.endpointConfig.credentialName,
              credentialPlacement: provider.endpointConfig.credentialPlacement,
              credentialPrefix: provider.endpointConfig.credentialPrefix,
              credentialSource: next,
              credentialTemplate: provider.endpointConfig.credentialTemplate,
              headers: provider.endpointConfig.headers,
              body: provider.endpointConfig.body,
              windows: provider.endpointConfig.windows,
              unknownFields: provider.endpointConfig.unknownFields,
            ),
          );
```

4. Call it from `upsert` (replace `final normalized = provider.copyWith(id: provider.id.trim());`):

```dart
    final trimmed = provider.copyWith(id: provider.id.trim());
    final normalized = await _ensurePerEntryBinding(trimmed);
```

5. Call it from `_loadInternal` (after `final providers = await _repository.load();`, before emitting ready):

```dart
      final migrated = <ManagedProvider>[];
      var changed = false;
      for (final provider in providers) {
        final next = await _ensurePerEntryBinding(provider);
        changed = changed || next != provider;
        migrated.add(next);
      }
      if (changed) {
        await _repository.save(migrated);
      }
      // then emit ready with `migrated` instead of `providers`
```

6. Wire in `client/lib/app/app_shell.dart` (~:950): add `appProviderCubit: appProviderCubit,` to the `ManagedProviderCubit(...)` construction. Note `appProviderCubit` is created at app_shell.dart:1127, **after** the `buildAppShell` wiring at :948 — check ordering: if `appProviderCubit` is not yet constructed where `ManagedProviderCubit` is built, hoist its construction above the managed-provider wiring (it only needs `flashskyaiExecutablePath` / `openCredentialLoginUrl`, both available earlier; move the assignment block up and keep the later reference). If hoisting is too invasive, instead defer row-ensuring lazily: have `ManagedProviderCubit` accept `AppProviderCubit? Function()? appProviderCubitProvider` and call it on demand. Prefer hoisting; fall back to the provider-function only if hoisting breaks other orderings.

- [ ] **Step 4: Run tests**

Run: `flutter test test/cubits/managed_provider_cubit_cli_binding_test.dart`
Expected: PASS.

Also run existing suite for regressions: `dart run tool/run_tests.dart test/pages/managed_providers/managed_provider_management_page_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/cubits/managed_provider_cubit.dart client/lib/app/app_shell.dart client/test/cubits/managed_provider_cubit_cli_binding_test.dart
git commit -m "Ensure and migrate per-entry CLI rows in ManagedProviderCubit"
```

---

### Task 5: Editor login UI binds to the per-entry row

**Files:**
- Modify: `client/lib/pages/managed_providers/managed_provider_official_credentials.dart`
- Test: `client/test/pages/managed_providers/managed_provider_management_page_test.dart` (extend)

**Interfaces:**
- Consumes: `ManagedProviderCliBinding` (Task 1), `AppProviderCubit` (existing), `ProviderCredentialActionBar` (unchanged).
- Produces: `ManagedProviderOfficialCredentials` widget with new required params `managedProviderId` (String) and `managedProviderName` (String); it looks up the row `'<cli>-mp-<managedProviderId>'` in `AppProviderCubit.state.providersFor(cli)` and falls back to `binding.rowTemplateFor(...)`; `ensureSaved` upserts the template row (persists before login IO). The editor page passes `_provider?.id ?? ''` — but the row can only be ensured **after** the managed provider id exists; for a brand-new entry the id is `managed-<now>` generated at save time. Therefore the widget also accepts `providerIdOverride` used when the editor has not saved yet: the editor generates the id when opening the "new" form and passes it down (see step 3).

- [ ] **Step 1: Write the failing widget test (extend the management page test file)**

Add to `client/test/pages/managed_providers/managed_provider_management_page_test.dart` `main()`:

```dart
  testWidgets(
    'Cursor preset login binds to a per-entry dedicated row',
    (tester) async {
      providerCubit.emit(
        ManagedProviderState(status: ManagedProviderLoadStatus.ready),
      );
      usageCubit.emit(
        ManagedProviderUsageState(status: ManagedProviderUsageLoadStatus.ready),
      );
      await pumpPage(tester);

      await openNewEditor(tester);
      await applyPreset(tester, 'Cursor');

      // The official credentials bar is present and reads the per-entry
      // binding (row id appears in the AppProviderCubit after login flow
      // start — here we assert the source field shows the per-entry form).
      expect(
        find.byKey(const Key('managed-provider-official-credentials')),
        findsOneWidget,
      );
      expect(find.text('Sign in with Cursor'), findsOneWidget);

      // Save the entry; the dedicated cursor row must be created.
      await tester.enterText(
        find.byKey(const Key('managed-provider-name')),
        'Team Cursor',
      );
      await tester.tap(find.byKey(const Key('managed-provider-save')));
      await tester.pumpAndSettle();

      final cursorRows = appProviderCubit.state.providersFor(CliTool.cursor);
      expect(
        cursorRows.any((row) => row.id.startsWith('cursor-mp-')),
        isTrue,
      );
      final saved = providerCubit.state.providers.first;
      expect(
        saved.endpointConfig.credentialSource,
        startsWith('cli:cursor-mp-'),
      );
    },
  );
```

Add `import 'package:teampilot/models/team_config.dart';` if not already imported. If `managed-provider-name` key does not exist in the editor, find the name field by `find.widgetWithText(TextFormField, …)` or the actual key used in `managed_provider_editor_sections.dart` (grep `Key('managed-provider-` for the real key, e.g. `managed-provider-name`).

- [ ] **Step 2: Run test to verify it fails**

Run: `dart run tool/run_tests.dart test/pages/managed_providers/managed_provider_management_page_test.dart --plain-name="Cursor preset login binds to a per-entry dedicated row"`
Expected: FAIL — saved source is `cli:cursor-account`; no `cursor-mp-*` row.

- [ ] **Step 3: Implement**

1. `client/lib/pages/managed_providers/managed_provider_editor_page.dart`:
   - Generate the entry id when the editor opens for a new provider (in `initState` when `_provider == null`): `late final String _entryId = _provider?.id ?? 'managed-${DateTime.now().millisecondsSinceEpoch}';` and use `_entryId` in `_save()` instead of recomputing (`final providerId = _entryId;`).
   - Pass the entry identity to the credentials widget (line ~234):

```dart
                    ? ManagedProviderOfficialCredentials(
                        credentialSource: _credentialSource.text.trim(),
                        managedProviderId: _entryId,
                        managedProviderName: _name.text.trim().isEmpty
                            ? _name.text
                            : _name.text.trim(),
                      )
```

2. Rewrite `client/lib/pages/managed_providers/managed_provider_official_credentials.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../models/app_provider_config.dart';
import '../../services/provider_usage/managed_provider_cli_binding.dart';
import '../../widgets/app_provider/provider_credential_action_bar.dart';

/// Login / import / revoke for `cli:` Managed Provider credential sources.
///
/// Binds to the entry's dedicated CLI provider row (`<cli>-mp-<entryId>`)
/// so login lands in that entry's isolated HOME.
class ManagedProviderOfficialCredentials extends StatefulWidget {
  const ManagedProviderOfficialCredentials({
    required this.credentialSource,
    required this.managedProviderId,
    required this.managedProviderName,
    super.key,
  });

  final String credentialSource;
  final String managedProviderId;
  final String managedProviderName;

  @override
  State<ManagedProviderOfficialCredentials> createState() =>
      _ManagedProviderOfficialCredentialsState();
}

class _ManagedProviderOfficialCredentialsState
    extends State<ManagedProviderOfficialCredentials> {
  static const _binding = ManagedProviderCliBinding();

  AppProviderConfig? _dedicatedRow() {
    final cli = _binding.cliForCredentialSource(widget.credentialSource);
    if (cli == null) return null;
    final rowId = managedProviderCliRowId(cli, widget.managedProviderId);
    final existing = context
        .read<AppProviderCubit>()
        .state
        .providersFor(cli)
        .where((row) => row.id == rowId)
        .firstOrNull;
    if (existing != null) return existing;
    return _binding.rowTemplateFor(
      cli,
      widget.managedProviderId,
      widget.managedProviderName,
    );
  }

  Future<AppProviderConfig?> _ensureSaved() async {
    final cli = _binding.cliForCredentialSource(widget.credentialSource);
    if (cli == null) return null;
    final rowId = managedProviderCliRowId(cli, widget.managedProviderId);
    final cubit = context.read<AppProviderCubit>();
    final existing = cubit.state
        .providersFor(cli)
        .where((row) => row.id == rowId)
        .firstOrNull;
    if (existing != null) return existing;
    final template = _binding.rowTemplateFor(
      cli,
      widget.managedProviderId,
      widget.managedProviderName,
    );
    if (template == null) return null;
    final ok = await cubit.upsertProvider(template);
    if (!ok) return null;
    return cubit.state
        .providersFor(cli)
        .where((row) => row.id == rowId)
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final row = _dedicatedRow();
    if (row == null) return const SizedBox.shrink();
    return BlocBuilder<AppProviderCubit, AppProviderState>(
      builder: (context, state) {
        final cli = row.cli;
        final rowId = row.id;
        final provider =
            state
                .providersFor(cli)
                .where((item) => item.id == rowId)
                .firstOrNull ??
            row;
        return ProviderCredentialActionBar(
          key: const Key('managed-provider-official-credentials'),
          provider: provider,
          ensureSaved: _ensureSaved,
        );
      },
    );
  }
}
```

3. The `credentialSource` shown in the editor for a **new** preset is still the preset's legacy string (`cli:cursor-account`) until save rewrites it (Task 4). The login bar binds to the dedicated row regardless (it derives the row from `managedProviderId`), which is correct: login before first save writes to the dedicated row, and save rewrites the source to match.

- [ ] **Step 4: Run tests**

Run: `dart run tool/run_tests.dart test/pages/managed_providers/managed_provider_management_page_test.dart`
Expected: PASS (including pre-existing "Codex/Cursor preset shows official login actions" tests — they only assert the bar and button exist).

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/pages/managed_providers/managed_provider_official_credentials.dart client/lib/pages/managed_providers/managed_provider_editor_page.dart client/test/pages/managed_providers/managed_provider_management_page_test.dart
git commit -m "Bind managed provider official login to per-entry dedicated rows"
```

---

### Task 6: Full verification

**Files:**
- No new files; verification pass.

- [ ] **Step 1: Analyzer**

Run: `cd /home/hhoa/git/hhoa/teampilot/client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no errors. Fix any unused imports (e.g. dropped `homeDirectory` in app_shell.dart) or removed-API references.

- [ ] **Step 2: Full test suite**

Run: `cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart`
Expected: PASS. Pay attention to:
- `test/services/provider_usage/*` (readers/resolver)
- `test/cubits/managed_provider_cubit_cli_binding_test.dart`
- `test/pages/managed_providers/managed_provider_management_page_test.dart`
- `test/app/app_shell_provider_usage_bootstrap_test.dart`
- Any test constructing `ManagedProviderCubit` without the new optional param (must still compile — all new params are optional).

- [ ] **Step 3: Manual smoke (if a desktop environment is available)**

Run the app, open 余额与用量 → 添加 → Cursor preset:
- Before login: the usage panel shows a credential-missing / query-failed state (NOT an auto-logged-in state) even if `~/.config/cursor/auth.json` exists.
- Click 登录 → complete device-code flow → usage query succeeds for this entry.
- Add a second Cursor preset entry → it has its own login state (not logged in) and after login its own usage numbers.
- `ls <teampilotRoot>/providers/cursor/` shows `cursor-mp-<entryId>/home/…` directories, one per logged-in entry.

If no desktop environment is available, skip and note it.

- [ ] **Step 4: Commit any fixes**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add -A client
git commit -m "Polish per-entry managed provider credentials"
```
