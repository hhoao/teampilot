# Per-Entry Credentials: Orphan Cleanup and No-Compat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the legacy shared-source compat layer entirely (legacy entries fail as unconfigured), delete the shared CLI provider rows (row + disk credentials), and reclaim orphaned per-entry rows via a delete hook plus a startup sweep.

**Architecture:** `ManagedProviderCliBinding` shrinks to per-entry-only recognition plus a new intent-source resolver (`cli:<cli>` → `cli:<cli>-mp-<entryId>`); the cubit's migration path is deleted (upsert only resolves intent sources and ensures the row); a new `ManagedProviderCliRowJanitor` service owns row+directory removal, called from the delete hook and a startup sweep; the three `defaultOfficialProviderId` capabilities return null.

**Tech Stack:** Flutter / Dart, flutter_bloc, in-repo `Filesystem` abstraction (`InMemoryFilesystem` in tests), no new packages.

**Spec:** `docs/superpowers/specs/2026-09-04-managed-provider-orphan-cleanup-no-compat-design.md`

## Global Constraints

- All commands run from `/home/hhoa/git/hhoa/teampilot/client`.
- Test command: `dart run tool/run_tests.dart test/<path>.dart` (or `flutter test test/<path>.dart` for plain flutter_test files). Before claiming done: `flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart` (40 failures in the user's uncommitted WIP areas — chat_view mocks, sidebar visibility — are pre-existing and out of scope; feature suites must be green).
- Per-entry row id format: `<cli.value>-mp-<managedProviderId>` via `managedProviderCliRowId(CliTool, String)` — never hardcode.
- Intent sources: exactly `cli:cursor`, `cli:claude`, `cli:codex` (preset templates only; resolved to per-entry before persistence).
- Legacy shared sources (`cli:cursor-account`, `cli:claude-official`, `cli:openai-official`) resolve to **null** everywhere — no migration, no recognition. Existing catalog entries with them load unchanged and render "credential not configured".
- Shared row ids to delete on sweep: `cursor-account` (cursor), `claude-official` (claude), `openai-official` (codex) — row + entire `providers/<cli>/<id>/` directory including credentials (irreversible, user-accepted).
- Disk layout: claude `providers/claude/<rowId>/`, codex `providers/codex/<rowId>/`, cursor `providers/cursor/<rowId>/home/` — remove the whole `<rowId>` directory recursively.
- Cleanup is best-effort: failures log via `appLogger.w` and never block entry deletion or startup.
- Never log or expose credential values.
- The working tree contains the user's uncommitted WIP (agent_runtime, chat_cubit, l10n, git_graph, app_shell formatter drift) — NEVER commit, stash, or revert files outside this plan's list. If a file you must touch also carries WIP edits (notably `app_shell.dart` has ~1400 lines of formatter drift), stage only your hunks (`git apply --cached` of an extracted patch, or `git add -p` non-interactively is impossible — prefer editing via a temporary patch file).

## Existing facts the implementer needs

- `ManagedProviderCliBinding` (`client/lib/services/provider_usage/managed_provider_cli_binding.dart`, 96 lines) — current shape has `_legacyByCli`, `legacySourceForCli`, `migrateCredentialSource`, `isPerEntrySource` (all to be removed) and `rowTemplateFor` (kept; `_legacyTemplates` renamed).
- `ManagedProviderCubit` (`client/lib/cubits/managed_provider_cubit.dart`) — `_loadInternal` has a migration block (lines ~107-175) to be deleted; `upsert` calls `_ensurePerEntryBinding` (line ~223); `_ensureCliRow` (line ~239) kept; `delete()` (line ~280) extended in Task 3. Constructor params: `repository`, `onProviderDeletedState`, `onProviderDeletedCredentialCleanup`, `appProviderCubit`, `binding`.
- `CliCredentialSourceResolver.read` (`cli_credential_source.dart:29-52`) delegates CLI resolution to `ManagedProviderCliBinding().cliForCredentialSource(source)` — no code change needed there; binding change automatically makes legacy sources throw `missingCredential`.
- Editor: `_applyPreset` (`managed_provider_editor_page.dart:401`) sets `_credentialSource.text = endpoint.credentialSource`; `_entryId` (line 77) is `late final String _entryId = _provider?.id ?? 'managed-<epochMillis>'`; `_save` uses `final providerId = _entryId;`.
- `AppProviderCubit` (`client/lib/cubits/app_provider_cubit.dart`) — has `upsertProvider`, `deleteProvider(id)` (uses `state.selectedCli` — do NOT use for other CLIs), `_repository` (private `AppProviderRepository`). Task 3 adds `loadProvidersFor` + `removeProviderRow`.
- `AppProviderRepository.loadProviders(cli, {reconcileCredentials})` / `saveProviders(cli, list)` exist.
- Presets: `managed_provider_presets.dart` — codex preset `credentialSource: 'cli:openai-official'` (:170), claude `'cli:claude-official'` (:213), cursor `'cli:cursor-account'` (:262).
- `defaultOfficialProviderId` overrides: claude `lib/services/cli/claude/capabilities/provider.dart:99`, cursor `lib/services/cli/cursor/capabilities/provider.dart:67`, codex `lib/services/cli/codex/capabilities/provider.dart:88`. Claude's `_resolveDefaultClaudeProviderId` (:808-826) has an `id == 'claude-official'` loop to remove.
- Logger: `appLogger.w(...)` / `appLogger.e(...)` from `package:teampilot/utils/logging/logger.dart` (global `appLogger`).
- app_shell wiring: `appProviderCubit` is constructed (hoisted) above the `ManagedProviderCubit` construction at ~:962; sweep wiring goes after the managed-provider control plane (~:975+).

---

### Task 1: Binding per-entry-only + intent sources + preset templates

**Files:**
- Modify: `client/lib/services/provider_usage/managed_provider_cli_binding.dart` (rewrite)
- Modify: `client/lib/services/provider_usage/managed_provider_presets.dart:170,213,262` (three source strings)
- Delete: `client/lib/services/provider_usage/official_managed_provider_binding.dart` + `client/test/services/provider_usage/official_managed_provider_binding_test.dart`
- Test: `client/test/services/provider_usage/managed_provider_cli_binding_test.dart` (rewrite), `client/test/services/provider_usage/managed_provider_presets_test.dart` (update)

**Interfaces:**
- Consumes: `CliTool`, `AppProviderConfig`, the three preset catalogs (unchanged).
- Produces (Tasks 2-4 rely on these exact signatures):
  - `CliTool? cliForCredentialSource(String source)` — **per-entry only** now: `cli:<cli.value>-mp-<nonEmptyId>` → cli; everything else (including legacy ids and bare intent sources) → null
  - `String? rowIdForCredentialSource(String source)` — unchanged semantics (`cli:<rowId>` → rowId)
  - `CliTool? intentCliForSource(String source)` — exact `cli:cursor` / `cli:claude` / `cli:codex` → cli; else null
  - `String? resolveIntentSource({required String source, required String managedProviderId})` — intent source → `'cli:<cli>-mp-<managedProviderId>'`; else null
  - `AppProviderConfig? rowTemplateFor(CliTool cli, String managedProviderId, String managedProviderName)` — unchanged
  - top-level `String managedProviderCliRowId(CliTool cli, String managedProviderId)` — unchanged
  - REMOVED: `isPerEntrySource`, `legacySourceForCli`, `migrateCredentialSource` — no consumer may reference them after this task

- [ ] **Step 1: Rewrite the binding test (TDD RED)**

Replace the contents of `client/test/services/provider_usage/managed_provider_cli_binding_test.dart`:

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

  test('cliForCredentialSource recognizes only per-entry sources', () {
    expect(
      binding.cliForCredentialSource('cli:cursor-mp-managed-1'),
      CliTool.cursor,
    );
    expect(binding.cliForCredentialSource('cli:claude-mp-m-1'), CliTool.claude);
    expect(binding.cliForCredentialSource('cli:codex-mp-m-1'), CliTool.codex);
    // Legacy shared sources are no longer recognized.
    expect(binding.cliForCredentialSource('cli:cursor-account'), isNull);
    expect(binding.cliForCredentialSource('cli:claude-official'), isNull);
    expect(binding.cliForCredentialSource('cli:openai-official'), isNull);
    // Intent sources are not row sources.
    expect(binding.cliForCredentialSource('cli:cursor'), isNull);
    expect(binding.cliForCredentialSource('secret'), isNull);
    expect(binding.cliForCredentialSource('cli:nope'), isNull);
    expect(binding.cliForCredentialSource('cli:cursor-mp-'), isNull);
  });

  test('intentCliForSource matches exact cli intent sources', () {
    expect(binding.intentCliForSource('cli:cursor'), CliTool.cursor);
    expect(binding.intentCliForSource('cli:claude'), CliTool.claude);
    expect(binding.intentCliForSource('cli:codex'), CliTool.codex);
    expect(binding.intentCliForSource('cli:cursor-mp-x'), isNull);
    expect(binding.intentCliForSource('cli:cursor-account'), isNull);
    expect(binding.intentCliForSource('secret'), isNull);
    expect(binding.intentCliForSource('cli:flashskyai'), isNull);
  });

  test('resolveIntentSource expands intent to per-entry', () {
    expect(
      binding.resolveIntentSource(
        source: 'cli:cursor',
        managedProviderId: 'managed-9',
      ),
      'cli:cursor-mp-managed-9',
    );
    expect(
      binding.resolveIntentSource(
        source: 'cli:claude',
        managedProviderId: 'managed-9',
      ),
      'cli:claude-mp-managed-9',
    );
    expect(
      binding.resolveIntentSource(
        source: 'cli:codex',
        managedProviderId: 'managed-9',
      ),
      'cli:codex-mp-managed-9',
    );
    // Already per-entry, legacy, and non-cli sources return null.
    expect(
      binding.resolveIntentSource(
        source: 'cli:cursor-mp-managed-9',
        managedProviderId: 'managed-9',
      ),
      isNull,
    );
    expect(
      binding.resolveIntentSource(
        source: 'cli:cursor-account',
        managedProviderId: 'managed-9',
      ),
      isNull,
    );
    expect(
      binding.resolveIntentSource(
        source: 'secret',
        managedProviderId: 'managed-9',
      ),
      isNull,
    );
  });

  test('rowIdForCredentialSource extracts row id', () {
    expect(
      binding.rowIdForCredentialSource('cli:cursor-mp-managed-1'),
      'cursor-mp-managed-1',
    );
    expect(binding.rowIdForCredentialSource('cli:cursor-account'), 'cursor-account');
    expect(binding.rowIdForCredentialSource('secret'), isNull);
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

    final codex = binding.rowTemplateFor(CliTool.codex, 'm1', 'Work');
    expect(codex?.id, 'codex-mp-m1');
    expect(codex?.isOfficial, isTrue);

    expect(binding.rowTemplateFor(CliTool.opencode, 'm1', 'X'), isNull);
  });
}
```

Also update `client/test/services/provider_usage/managed_provider_presets_test.dart` — find the assertion expecting `'cli:cursor-account'` (around :39) and the equivalent codex/claude assertions; change them to:

```dart
    expect(
      cursorPreset.template.endpointConfig.credentialSource,
      'cli:cursor',
    );
```

(and `cli:claude` / `cli:codex` for the other two presets; adapt to the file's actual variable names).

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/provider_usage/managed_provider_cli_binding_test.dart test/services/provider_usage/managed_provider_presets_test.dart`
Expected: FAIL — `intentCliForSource`/`resolveIntentSource` don't exist; legacy-recognition assertions fail; presets still carry legacy sources.

- [ ] **Step 3: Rewrite the binding**

Replace the whole of `client/lib/services/provider_usage/managed_provider_cli_binding.dart`:

```dart
import '../../models/app_provider_config.dart';
import '../cli/claude/provider_presets.dart';
import '../cli/codex/provider_presets.dart';
import '../cli/cursor/provider_presets.dart';

/// Per-entry CLI provider row binding for managed-provider `cli:` sources.
///
/// A managed-provider entry that uses an official CLI credential source owns
/// a dedicated CLI provider row (`<cli>-mp-<managedProviderId>`) whose
/// isolated HOME holds that entry's login. Only per-entry sources are
/// recognized: preset templates carry an intent source (`cli:cursor`) that
/// the editor / cubit expands to the per-entry source before persistence.
class ManagedProviderCliBinding {
  const ManagedProviderCliBinding();

  static const _officialClis = <CliTool>{
    CliTool.cursor,
    CliTool.claude,
    CliTool.codex,
  };

  static const _officialTemplates = <CliTool, AppProviderConfig Function()>{
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

  /// CLI for a per-entry credential source (`cli:<cli>-mp-<entryId>`).
  ///
  /// Legacy shared sources (`cli:cursor-account`, …) and intent sources
  /// (`cli:cursor`) return null — only per-entry sources are valid here.
  CliTool? cliForCredentialSource(String source) {
    final rowId = rowIdForCredentialSource(source);
    if (rowId == null) return null;
    for (final cli in _officialClis) {
      // `<cli>-mp-` with an empty trailing provider id segment is malformed.
      if (rowId == '${cli.value}-mp-') return null;
      if (rowId.startsWith('${cli.value}-mp-')) return cli;
    }
    return null;
  }

  String? rowIdForCredentialSource(String source) {
    const prefix = 'cli:';
    if (!source.startsWith(prefix)) return null;
    final rowId = source.substring(prefix.length).trim();
    return rowId.isEmpty ? null : rowId;
  }

  /// CLI named by a preset intent source (`cli:cursor`, `cli:claude`,
  /// `cli:codex`). Row sources and unknown values return null.
  CliTool? intentCliForSource(String source) {
    final trimmed = source.trim();
    for (final cli in _officialClis) {
      if (trimmed == 'cli:${cli.value}') return cli;
    }
    return null;
  }

  /// Expands an intent source to the entry's per-entry source, or null when
  /// [source] is not an intent source (already per-entry, legacy, non-cli).
  String? resolveIntentSource({
    required String source,
    required String managedProviderId,
  }) {
    final cli = intentCliForSource(source);
    if (cli == null) return null;
    return 'cli:${managedProviderCliRowId(cli, managedProviderId)}';
  }

  /// Dedicated CLI provider row for a managed-provider entry, or `null` for
  /// CLIs without an official preset.
  AppProviderConfig? rowTemplateFor(
    CliTool cli,
    String managedProviderId,
    String managedProviderName,
  ) {
    final templateFactory = _officialTemplates[cli];
    if (templateFactory == null) return null;
    final preset = templateFactory();
    return preset.copyWith(
      id: managedProviderCliRowId(cli, managedProviderId),
      name: '${preset.name} ($managedProviderName)',
    );
  }
}

String managedProviderCliRowId(CliTool cli, String managedProviderId) =>
    '${cli.value}-mp-${managedProviderId.trim()}';
```

Update the three preset sources in `client/lib/services/provider_usage/managed_provider_presets.dart`:
- `:170` `credentialSource: 'cli:openai-official',` → `credentialSource: 'cli:codex',`
- `:213` `credentialSource: 'cli:claude-official',` → `credentialSource: 'cli:claude',`
- `:262` `credentialSource: 'cli:cursor-account',` → `credentialSource: 'cli:cursor',`

Delete the dead binding:
```bash
cd /home/hhoa/git/hhoa/teampilot
git rm client/lib/services/provider_usage/official_managed_provider_binding.dart \
       client/test/services/provider_usage/official_managed_provider_binding_test.dart
```

Then grep for any remaining reference: `grep -rn "OfficialManagedProviderBinding\|ensureOfficialAppProvider\|migrateCredentialSource\|legacySourceForCli\|isPerEntrySource" client/lib client/test` — expected: zero hits. (If the editor page or others still import the deleted file, remove those imports — they were already removed in commit `bde3007f6`; verify.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/provider_usage/managed_provider_cli_binding_test.dart test/services/provider_usage/managed_provider_presets_test.dart`
Expected: PASS.

Note: other suites (resolver, adapter, cubit, editor) will now FAIL because they use legacy sources — that is Task 2's scope. Do not fix them here. Do not run the full suite yet.

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/provider_usage/managed_provider_cli_binding.dart \
        client/lib/services/provider_usage/managed_provider_presets.dart \
        client/test/services/provider_usage/managed_provider_cli_binding_test.dart \
        client/test/services/provider_usage/managed_provider_presets_test.dart
git commit -m "Restrict managed provider cli binding to per-entry sources"
```

---

### Task 2: Cubit/editor intent resolution; remove migration; update dependent tests

**Files:**
- Modify: `client/lib/cubits/managed_provider_cubit.dart` (remove migration block, rename `_ensurePerEntryBinding` → `_bindIntentSource`)
- Modify: `client/lib/pages/managed_providers/managed_provider_editor_page.dart` (`_applyPreset` intent conversion)
- Modify: `client/lib/pages/managed_providers/managed_provider_editor_sections.dart:396` (example text)
- Modify: `client/lib/l10n/app_en.arb` + `app_zh.arb` (credential-source hint example)
- Test: `client/test/cubits/managed_provider_cubit_cli_binding_test.dart` (rewrite), `client/test/services/provider_usage/cli_credential_source_test.dart` (update), `client/test/services/provider_usage/official_subscription_auth_test.dart` (drop legacy test), `client/test/services/provider_usage/http_json_mapping_adapter_test.dart` (update sources), `client/test/app/app_shell_provider_usage_bootstrap_test.dart` (update source)

**Interfaces:**
- Consumes: Task 1 binding — `resolveIntentSource({source, managedProviderId})`, `cliForCredentialSource`, `rowIdForCredentialSource`, `managedProviderCliRowId`.
- Produces: `ManagedProviderCubit.upsert` expands intent sources to per-entry before persisting and ensures the dedicated row (existing `_ensureCliRow`); `load()` performs no rewriting or row-ensuring; `_bindIntentSource(ManagedProvider)` private helper replaces `_ensurePerEntryBinding`.

- [ ] **Step 1: Rewrite the cubit test (TDD RED)**

Replace the contents of `client/test/cubits/managed_provider_cubit_cli_binding_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/managed_provider_cubit.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late ManagedProviderRepository repo;
  late _UsageRepoStub usageRepo;

  setUp(() {
    fs = InMemoryFilesystem();
    usageRepo = _UsageRepoStub();
    repo = ManagedProviderRepository(
      fs: fs,
      configPath: '/tp/managed-providers.json',
      onProvidersDeleted: usageRepo.deleteMany,
    );
  });

  ManagedProvider _entry({
    required String id,
    String source = 'cli:cursor',
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

  AppProviderCubit _appCubit() => AppProviderCubit(
    repository: AppProviderRepository(fs: fs, basePath: '/tp'),
    basePath: '/tp',
  );

  test('upsert expands an intent source to the per-entry source', () async {
    final appCubit = _appCubit();
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
    expect(
      appCubit.state
          .providersFor(CliTool.cursor)
          .any((row) => row.id == 'cursor-mp-managed-1'),
      isTrue,
    );
    await cubit.close();
    await appCubit.close();
  });

  test('upsert leaves already per-entry sources unchanged', () async {
    await repo.save([
      _entry(id: 'managed-2', source: 'cli:cursor-mp-managed-2'),
    ]);
    final appCubit = _appCubit();
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

  test('load leaves legacy-source entries untouched and un-migrated',
      () async {
    await repo.save([_entry(id: 'managed-3', source: 'cli:cursor-account')]);
    final appCubit = _appCubit();
    final cubit = ManagedProviderCubit(
      repository: repo,
      appProviderCubit: appCubit,
    );
    await cubit.load();

    final loaded = cubit.state.providerFor('managed-3')!;
    // No migration, no row ensure: the entry stays exactly as on disk and
    // no dedicated row is created for it.
    expect(
      loaded.endpointConfig.credentialSource,
      'cli:cursor-account',
    );
    expect(
      appCubit.state
          .providersFor(CliTool.cursor)
          .any((row) => row.id.startsWith('cursor-mp-')),
      isFalse,
    );
    final persisted = await repo.load();
    expect(
      persisted.first.endpointConfig.credentialSource,
      'cli:cursor-account',
    );
    await cubit.close();
    await appCubit.close();
  });
}

/// Minimal stub matching ManagedProviderUsageRepository.deleteMany.
class _UsageRepoStub {
  Future<void> deleteMany(List<String> ids) async {}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/cubits/managed_provider_cubit_cli_binding_test.dart`
Expected: FAIL — upsert doesn't expand intent sources; load still migrates legacy entries.

- [ ] **Step 3: Implement the cubit changes**

In `client/lib/cubits/managed_provider_cubit.dart`:

1. Replace the migration block in `_loadInternal` — from `final migrated = <ManagedProvider>[];` through the end of the `if (changed) { ... return; }` block and the trailing plain emit — with the simple form:

```dart
    try {
      final providers = await _repository.load();
      if (isClosed || revision != _catalogRevision) return;
      emit(
        state.copyWith(
          status: ManagedProviderLoadStatus.ready,
          providers: providers,
          clearError: true,
        ),
      );
    } on Object {
      // unchanged existing error emit
    }
```

(Keep the existing `emit(loading)` preamble and error handler; only the body between changes. The serialized-save merge block is deleted wholesale — load never saves now.)

2. Replace `_ensurePerEntryBinding` with:

```dart
  /// Expands a preset intent source (`cli:cursor`) to the per-entry source
  /// and ensures the dedicated CLI provider row exists. Legacy and already
  /// per-entry sources pass through unchanged.
  Future<ManagedProvider> _bindIntentSource(ManagedProvider provider) async {
    final source = provider.endpointConfig.credentialSource.trim();
    final next = _binding.resolveIntentSource(
      source: source,
      managedProviderId: provider.id,
    );
    if (next == null) {
      await _ensureCliRow(provider);
      return provider;
    }
    final bound = provider.copyWith(
      endpointConfig: _withCredentialSource(provider.endpointConfig, next),
    );
    await _ensureCliRow(bound);
    return bound;
  }

  static ManagedProviderEndpointConfig _withCredentialSource(
    ManagedProviderEndpointConfig config,
    String credentialSource,
  ) => ManagedProviderEndpointConfig(
    url: config.url,
    method: config.method,
    responsePath: config.responsePath,
    credentialField: config.credentialField,
    credentialName: config.credentialName,
    credentialPlacement: config.credentialPlacement,
    credentialPrefix: config.credentialPrefix,
    credentialSource: credentialSource,
    credentialTemplate: config.credentialTemplate,
    headers: config.headers,
    body: config.body,
    windows: config.windows,
    hadUnsafeUrl: config.hadUnsafeUrl,
    unknownFields: config.unknownFields,
  );
```

(Extract the full-field constructor currently inline in `_ensurePerEntryBinding` into `_withCredentialSource` — the field list is identical to what's there now.)

3. In `upsert`, change the call `final normalized = await _ensurePerEntryBinding(trimmed);` → `final normalized = await _bindIntentSource(trimmed);`

4. In the editor `client/lib/pages/managed_providers/managed_provider_editor_page.dart`, `_applyPreset` — after `_credentialSource.text = endpoint.credentialSource;` insert the intent expansion so pre-save login binds to the dedicated row and save persists the per-entry source. Replace the single line with:

```dart
      final presetSource = endpoint.credentialSource;
      final intentCli = ManagedProviderCliBinding().intentCliForSource(
        presetSource,
      );
      _credentialSource.text = intentCli == null
          ? presetSource
          : 'cli:${managedProviderCliRowId(intentCli, _entryId)}';
```

(Note: `_applyPreset`'s setState block — put the `final` declarations before `setState` and only the assignment inside it. `_entryId` is `late final` and already available.)

5. Update the hint/example texts:
- `client/lib/pages/managed_providers/managed_provider_editor_sections.dart:396` — `example: 'cli:cursor-account',` → `example: 'cli:cursor-mp-<entry>',`
- `client/lib/l10n/app_en.arb` and `client/lib/l10n/app_zh.arb` — find the `managedProvidersCredentialSourceHint` entries containing `cli:cursor-account` and change the example to `cli:cursor-mp-<entry>` (keep both locales in sync). Regeneration of `app_localizations*.dart` happens automatically on the next `flutter test`/`flutter analyze` — if the generated files don't update, run `flutter gen-l10n` from `client/`.

- [ ] **Step 4: Update dependent tests**

a) `client/test/services/provider_usage/cli_credential_source_test.dart` — the legacy tests must now expect `missingCredential`:
- `'cli:cursor-account prefers isolated auth.json'` — change source to `'cli:cursor-mp-p1'` and the credential file paths from `providers/cursor/cursor-account/home` to `providers/cursor/cursor-mp-p1/home` (rename the test `'cli:cursor-mp-p1 resolves the isolated auth.json'`).
- `'legacy cursor-account source resolves through the cursor reader'` — replace with:

```dart
  test('legacy cursor-account source is missingCredential', () async {
    final fs = InMemoryFilesystem();
    final layout = CursorHomeLayout(pathContext: fs.pathContext);
    await fs.writeString(
      layout.authJson('/tp/providers/cursor/cursor-account/home'),
      jsonEncode({'accessToken': 'legacy-token'}),
    );
    await expectLater(
      CliCredentialSourceResolver(
        readers: {
          'cursor': CursorOfficialSubscriptionAuthReader(
            fs: fs,
            basePath: '/tp',
          ),
        },
      ).read('cli:cursor-account'),
      throwsA(isA<ManagedProviderUsageQueryError>().having(
        (e) => e.code,
        'code',
        ManagedProviderUsageQueryErrorCode.missingCredential,
      )),
    );
  });
```

- Also change the per-entry routing tests' reader keys/sources only if they used legacy strings — `cli:cursor-mp-managed-7` / `cli:claude-mp-managed-7` forms stay valid.

b) `client/test/services/provider_usage/official_subscription_auth_test.dart` — delete the test `'Legacy shared rows still resolve through the isolated directory'` (the resolver never routes legacy ids anymore; keep the reader-level per-entry tests).

c) `client/test/services/provider_usage/http_json_mapping_adapter_test.dart` — every `credentialSource: 'cli:cursor-account'` (inline, ~:987 and ~:1036) becomes `'cli:cursor-mp-p1'`; tests that build providers from `managedProviderPresetById(...)` templates must override the source after copying the template (the template now carries the intent source `cli:cursor`, which the resolver rejects), e.g.:

```dart
      endpointConfig: presetTemplate.endpointConfig.copyWith(
        credentialSource: 'cli:claude-mp-p1',
      ),
```

If `ManagedProviderEndpointConfig` has no `copyWith` in your working tree, construct the endpoint config explicitly (mirror the existing test's field list, swapping only `credentialSource`). Grep the file for `'cli:` to find every site.

d) `client/test/app/app_shell_provider_usage_bootstrap_test.dart` — the `'file-backed cli auth resolves credentials for http-json fetch'` test: change `credentialSource: 'cli:claude-official'` to `'cli:claude-mp-p1'` and the credential file write path from `/tp/providers/claude/claude-official/.credentials.json` to `/tp/providers/claude/claude-mp-p1/.credentials.json`.

e) `client/test/pages/managed_providers/managed_provider_management_page_test.dart` — the two per-entry tests ('Cursor preset login binds to a per-entry dedicated row', 'reopened per-entry provider still shows the official login bar') must still pass unchanged (the editor now expands the intent at preset-apply; the assertions `startsWith('cli:cursor-mp-')` hold). Run them; if the harness's AppProviderCubit starts empty they already pass.

- [ ] **Step 5: Run the affected suites**

Run: `flutter test test/cubits/managed_provider_cubit_cli_binding_test.dart test/services/provider_usage/ test/app/app_shell_provider_usage_bootstrap_test.dart test/pages/managed_providers/managed_provider_management_page_test.dart`
Expected: PASS (all).

- [ ] **Step 6: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/cubits/managed_provider_cubit.dart \
        client/lib/pages/managed_providers/managed_provider_editor_page.dart \
        client/lib/pages/managed_providers/managed_provider_editor_sections.dart \
        client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
        client/lib/l10n/app_localizations.dart \
        client/lib/l10n/app_localizations_en.dart \
        client/lib/l10n/app_localizations_zh.dart \
        client/test/cubits/managed_provider_cubit_cli_binding_test.dart \
        client/test/services/provider_usage/ \
        client/test/app/app_shell_provider_usage_bootstrap_test.dart \
        client/test/pages/managed_providers/managed_provider_management_page_test.dart
git commit -m "Expand intent sources at save and drop legacy migration"
```

(If the l10n generated files did not change, drop them from the `git add` list. Only add files this task touched.)

---

### Task 3: Janitor — delete hook + startup sweep

**Files:**
- Modify: `client/lib/cubits/app_provider_cubit.dart` (add `loadProvidersFor` + `removeProviderRow`)
- Create: `client/lib/services/provider_usage/managed_provider_cli_row_janitor.dart`
- Modify: `client/lib/cubits/managed_provider_cubit.dart` (delete hook + `rowJanitor` param)
- Modify: `client/lib/app/app_shell.dart` (janitor construction, cubit wiring, sweep trigger)
- Test: `client/test/services/provider_usage/managed_provider_cli_row_janitor_test.dart` (new), `client/test/cubits/managed_provider_cubit_cli_binding_test.dart` (extend)

**Interfaces:**
- Consumes: Task 1 binding (`cliForCredentialSource`, `rowIdForCredentialSource`); `AppProviderRepository.loadProviders/saveProviders`; `Filesystem.removeRecursive`; `appLogger`.
- Produces:
  - `AppProviderCubit.loadProvidersFor(CliTool cli) → Future<List<AppProviderConfig>>`
  - `AppProviderCubit.removeProviderRow(CliTool cli, String providerId) → Future<void>`
  - `ManagedProviderCliRowJanitor({required Filesystem fs, required String basePath, AppProviderCubit? appProviderCubit})`
  - `Future<void> removeDedicatedRow({required CliTool cli, required String rowId})` — removes the catalog row (when the cubit is present) and the disk directory `providers/<cli>/<rowId>/`
  - `Future<void> sweep({required Iterable<ManagedProvider> entries})` — reclaims orphan `-mp-` rows and deletes the shared rows
  - `ManagedProviderCubit` constructor param `ManagedProviderCliRowJanitor? rowJanitor`

- [ ] **Step 1: Write the failing janitor test**

Create `client/test/services/provider_usage/managed_provider_cli_row_janitor_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/provider_usage/managed_provider_cli_row_janitor.dart';

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

  AppProviderConfig _row(String id) => AppProviderConfig(
    id: id,
    cli: CliTool.cursor,
    name: 'Row $id',
  );

  ManagedProvider _entry(String id, String source) => ManagedProvider(
    id: id,
    name: 'Entry $id',
    kind: ManagedProviderKind.subscriptionQuota,
    adapterId: 'http-json',
    endpointConfig: ManagedProviderEndpointConfig(
      url: 'https://cursor.com/api/usage-summary',
      credentialSource: source,
    ),
  );

  test('removeDedicatedRow deletes the catalog row and disk directory',
      () async {
    await appCubit.upsertProvider(_row('cursor-mp-managed-1'));
    await fs.ensureDir('/tp/providers/cursor/cursor-mp-managed-1/home/.config/cursor');
    await fs.writeString(
      '/tp/providers/cursor/cursor-mp-managed-1/home/.config/cursor/auth.json',
      '{"accessToken":"tok"}',
    );

    await ManagedProviderCliRowJanitor(
      fs: fs,
      basePath: '/tp',
      appProviderCubit: appCubit,
    ).removeDedicatedRow(cli: CliTool.cursor, rowId: 'cursor-mp-managed-1');

    expect(
      appCubit.state
          .providersFor(CliTool.cursor)
          .any((row) => row.id == 'cursor-mp-managed-1'),
      isFalse,
    );
    expect((await fs.stat('/tp/providers/cursor/cursor-mp-managed-1')).exists,
        isFalse);
  });

  test('removeDedicatedRow tolerates a missing row and directory',
      () async {
    await ManagedProviderCliRowJanitor(
      fs: fs,
      basePath: '/tp',
      appProviderCubit: appCubit,
    ).removeDedicatedRow(cli: CliTool.codex, rowId: 'codex-mp-none');
    // No throw; nothing to assert beyond reaching here.
  }, skip: false);

  test('sweep reclaims orphan -mp- rows and shared rows, keeps live ones',
      () async {
    await appCubit.upsertProvider(_row('cursor-mp-managed-live'));
    await appCubit.upsertProvider(_row('cursor-mp-managed-orphan'));
    await appCubit.upsertProvider(_row('cursor-account'));
    await appCubit.upsertProvider(_row('cursor-other'));
    await fs.ensureDir('/tp/providers/cursor/cursor-mp-managed-orphan/home');
    await fs.ensureDir('/tp/providers/cursor/cursor-account/home');

    await ManagedProviderCliRowJanitor(
      fs: fs,
      basePath: '/tp',
      appProviderCubit: appCubit,
    ).sweep(entries: [_entry('managed-live', 'cli:cursor-mp-managed-live')]);

    final remaining =
        appCubit.state.providersFor(CliTool.cursor).map((r) => r.id).toSet();
    expect(remaining, {'cursor-mp-managed-live', 'cursor-other'});
    expect(
      (await fs.stat('/tp/providers/cursor/cursor-mp-managed-orphan')).exists,
      isFalse,
    );
    expect(
      (await fs.stat('/tp/providers/cursor/cursor-account')).exists,
      isFalse,
    );
  });

  test('sweep is a no-op on empty catalogs', () async {
    await ManagedProviderCliRowJanitor(
      fs: fs,
      basePath: '/tp',
      appProviderCubit: appCubit,
    ).sweep(entries: const []);
    expect(appCubit.state.providersFor(CliTool.cursor), isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/services/provider_usage/managed_provider_cli_row_janitor_test.dart`
Expected: FAIL — `managed_provider_cli_row_janitor.dart` does not exist.

- [ ] **Step 3: Implement AppProviderCubit additions + the janitor**

In `client/lib/cubits/app_provider_cubit.dart`, add after `deleteProvider`:

```dart
  /// Providers for [cli], loading from the repository on first access.
  Future<List<AppProviderConfig>> loadProvidersFor(CliTool cli) async =>
      state.providersByCli[cli] ?? await _repository.loadProviders(cli);

  /// Removes one provider row for an explicit CLI (unlike [deleteProvider],
  /// which operates on the currently selected CLI).
  Future<void> removeProviderRow(CliTool cli, String providerId) async {
    final trimmed = providerId.trim();
    if (trimmed.isEmpty) return;
    final current = await loadProvidersFor(cli);
    final filtered = current.where((p) => p.id != trimmed).toList();
    if (filtered.length == current.length) return;
    await _repository.saveProviders(cli, filtered);
    emit(
      state.copyWith(
        providersByCli: {...state.providersByCli, cli: filtered},
        selectedProviderIdByCli: {
          ...state.selectedProviderIdByCli,
          cli: filtered.any((p) => p.id == state.selectedProviderIdByCli[cli])
              ? state.selectedProviderIdByCli[cli]
              : filtered.firstOrNull?.id,
        },
        statusMessage: 'Provider removed.',
      ),
    );
  }
```

Create `client/lib/services/provider_usage/managed_provider_cli_row_janitor.dart`:

```dart
import 'dart:async';

import '../../models/app_provider_config.dart';
import '../../models/managed_provider.dart';
import '../../models/team_config.dart';
import '../../cubits/app_provider_cubit.dart';
import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import 'managed_provider_cli_binding.dart';

/// Removes dedicated CLI provider rows and their isolated HOME directories.
///
/// Owned by the managed-provider delete hook (entry deleted → row + disk
/// credentials gone) and the startup sweep (orphaned `-mp-` rows and the
/// legacy shared rows are reclaimed). All operations are best-effort:
/// failures are logged and never propagate to callers.
class ManagedProviderCliRowJanitor {
  ManagedProviderCliRowJanitor({
    required Filesystem fs,
    required String basePath,
    AppProviderCubit? appProviderCubit,
  }) : _fs = fs,
       _basePath = basePath.trim(),
       _appProviderCubit = appProviderCubit;

  static const _sharedRowIds = <CliTool, String>{
    CliTool.cursor: 'cursor-account',
    CliTool.claude: 'claude-official',
    CliTool.codex: 'openai-official',
  };

  static const _clis = <CliTool>{
    CliTool.cursor,
    CliTool.claude,
    CliTool.codex,
  };

  final Filesystem _fs;
  final String _basePath;
  final AppProviderCubit? _appProviderCubit;

  /// Removes [rowId] from [cli]'s catalog and deletes
  /// `providers/<cli>/<rowId>/` from disk (credentials included).
  Future<void> removeDedicatedRow({
    required CliTool cli,
    required String rowId,
  }) async {
    final cubit = _appProviderCubit;
    if (cubit != null) {
      try {
        await cubit.removeProviderRow(cli, rowId);
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[managed-provider] failed to remove CLI row $rowId: $error',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    await _removeProviderDir(cli, rowId);
  }

  /// Deletes orphaned `-mp-` rows (no corresponding managed-provider entry)
  /// and the legacy shared rows. Never creates or rewrites rows.
  Future<void> sweep({required Iterable<ManagedProvider> entries}) async {
    final binding = const ManagedProviderCliBinding();
    final liveRowIds = <String>{
      for (final entry in entries)
        binding.rowIdForCredentialSource(
              entry.endpointConfig.credentialSource.trim(),
            ) ??
            '',
    }..remove('');
    final cubit = _appProviderCubit;
    for (final cli in _clis) {
      final List<AppProviderConfig> rows;
      try {
        rows = cubit == null
            ? const []
            : await cubit.loadProvidersFor(cli);
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[managed-provider] sweep failed to load ${cli.value} rows: $error',
          error: error,
          stackTrace: stackTrace,
        );
        continue;
      }
      for (final row in rows) {
        final isShared = row.id == _sharedRowIds[cli];
        final isOrphan = row.id.startsWith('${cli.value}-mp-') &&
            !liveRowIds.contains(row.id);
        if (!isShared && !isOrphan) continue;
        await removeDedicatedRow(cli: cli, rowId: row.id);
      }
    }
  }

  Future<void> _removeProviderDir(CliTool cli, String rowId) async {
    final dir = _fs.pathContext.join(
      _basePath,
      'providers',
      cli.value,
      rowId.trim(),
    );
    try {
      if ((await _fs.stat(dir)).exists) {
        await _fs.removeRecursive(dir);
      }
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[managed-provider] failed to remove directory $dir: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
```

(Adjust the `appLogger.w` signature if `AppLogger` doesn't take `error:`/`stackTrace:` named params — check an existing call site like `lib/repositories/session_repository.dart:1332` and mirror it.)

- [ ] **Step 4: Wire the delete hook into the cubit (TDD)**

Add to `client/test/cubits/managed_provider_cubit_cli_binding_test.dart` (inside `main()`, after the existing tests):

```dart
  test('delete removes the dedicated CLI row and its directory', () async {
    final appCubit = _appCubit();
    final janitor = ManagedProviderCliRowJanitor(
      fs: fs,
      basePath: '/tp',
      appProviderCubit: appCubit,
    );
    final cubit = ManagedProviderCubit(
      repository: repo,
      appProviderCubit: appCubit,
      rowJanitor: janitor,
    );
    await cubit.upsert(_entry(id: 'managed-4'));
    await fs.ensureDir('/tp/providers/cursor/cursor-mp-managed-4/home');

    await cubit.delete('managed-4');

    expect(cubit.state.providerFor('managed-4'), isNull);
    expect(
      appCubit.state
          .providersFor(CliTool.cursor)
          .any((row) => row.id == 'cursor-mp-managed-4'),
      isFalse,
    );
    expect(
      (await fs.stat('/tp/providers/cursor/cursor-mp-managed-4')).exists,
      isFalse,
    );
    await cubit.close();
    await appCubit.close();
  });

  test('delete of a non-cli entry has no CLI side effects', () async {
    final appCubit = _appCubit();
    await appCubit.upsertProvider(AppProviderConfig(
      id: 'cursor-keep',
      cli: CliTool.cursor,
      name: 'Keep',
    ));
    final janitor = ManagedProviderCliRowJanitor(
      fs: fs,
      basePath: '/tp',
      appProviderCubit: appCubit,
    );
    final cubit = ManagedProviderCubit(
      repository: repo,
      appProviderCubit: appCubit,
      rowJanitor: janitor,
    );
    await repo.save([
      ManagedProvider(
        id: 'managed-5',
        name: 'API balance',
        kind: ManagedProviderKind.apiBalance,
        adapterId: 'http-json',
        endpointConfig: ManagedProviderEndpointConfig(
          url: 'https://example.test/usage',
          credentialSource: 'secret',
        ),
      ),
    ]);

    await cubit.delete('managed-5');

    expect(
      appCubit.state
          .providersFor(CliTool.cursor)
          .any((row) => row.id == 'cursor-keep'),
      isTrue,
    );
    await cubit.close();
    await appCubit.close();
  });
```

(Add the janitor import: `import 'package:teampilot/services/provider_usage/managed_provider_cli_row_janitor.dart';` and `import 'package:teampilot/models/app_provider_config.dart';`.)

In `client/lib/cubits/managed_provider_cubit.dart`:

1. Constructor gains `ManagedProviderCliRowJanitor? rowJanitor,` (store as `_rowJanitor`), plus the import `'../services/provider_usage/managed_provider_cli_row_janitor.dart'`.
2. In `delete()`, inside `_serializeMutation`, after the existing `onProviderDeletedState` call and before the final emit, add:

```dart
      await _removeDedicatedCliRow(provider);
```

3. Add the helper:

```dart
  /// Best-effort removal of the entry's dedicated CLI row and its isolated
  /// HOME directory. Failures are logged by the janitor and never fail the
  /// entry deletion.
  Future<void> _removeDedicatedCliRow(ManagedProvider? provider) async {
    final janitor = _rowJanitor;
    if (janitor == null || provider == null) return;
    final source = provider.endpointConfig.credentialSource.trim();
    final cli = _binding.cliForCredentialSource(source);
    final rowId = _binding.rowIdForCredentialSource(source);
    if (cli == null || rowId == null) return;
    await janitor.removeDedicatedRow(cli: cli, rowId: rowId);
  }
```

- [ ] **Step 5: Run janitor + cubit tests**

Run: `flutter test test/services/provider_usage/managed_provider_cli_row_janitor_test.dart test/cubits/managed_provider_cubit_cli_binding_test.dart`
Expected: PASS.

- [ ] **Step 6: Wire app_shell**

In `client/lib/app/app_shell.dart`:

1. Import the janitor: `import '../services/provider_usage/managed_provider_cli_row_janitor.dart';`
2. After `appProviderCubit` is constructed (hoisted position, before the `ManagedProviderCubit` wiring at ~:962), add:

```dart
  final managedProviderCliRowJanitor = ManagedProviderCliRowJanitor(
    fs: AppStorage.fs,
    basePath: AppStorage.paths.basePath,
    appProviderCubit: appProviderCubit,
  );
```

3. Add `rowJanitor: managedProviderCliRowJanitor,` to the `ManagedProviderCubit(...)` construction.
4. After the `ManagedProviderControlPlane` construction (~:975), add the one-shot sweep (fire-and-forget, failure-tolerant):

```dart
  unawaited(
    () async {
      try {
        final entries = await resolvedManagedProviderRepository.load();
        await managedProviderCliRowJanitor.sweep(entries: entries);
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[managed-provider] cli row sweep failed: $error',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }(),
  );
```

(`unawaited` needs `dart:async` — already imported in app_shell.dart.)

CAUTION: `app_shell.dart` carries ~1400 lines of the user's uncommitted formatter drift. Do NOT `git add` the whole file. Extract your hunks to a patch and `git apply --cached` it, or use `git diff > /tmp/full.patch`, hand-split, and stage selectively. Verify with `git diff --cached -- client/lib/app/app_shell.dart` that only your wiring hunks are staged.

- [ ] **Step 7: Run broader suites**

Run: `flutter test test/services/provider_usage/ test/cubits/managed_provider_cubit_cli_binding_test.dart test/app/app_shell_provider_usage_bootstrap_test.dart test/pages/managed_providers/managed_provider_management_page_test.dart`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/cubits/app_provider_cubit.dart \
        client/lib/services/provider_usage/managed_provider_cli_row_janitor.dart \
        client/lib/cubits/managed_provider_cubit.dart \
        client/test/services/provider_usage/managed_provider_cli_row_janitor_test.dart \
        client/test/cubits/managed_provider_cubit_cli_binding_test.dart
# app_shell.dart: stage ONLY your hunks (see caution above), then:
git add client/lib/app/app_shell.dart
git commit -m "Reclaim dedicated CLI rows on delete and at startup"
```

---

### Task 4: defaultOfficialProviderId → null; generalize claude default

**Files:**
- Modify: `client/lib/services/cli/claude/capabilities/provider.dart:99,808-826`
- Modify: `client/lib/services/cli/cursor/capabilities/provider.dart:67`
- Modify: `client/lib/services/cli/codex/capabilities/provider.dart:88`
- Test: run affected suites; add a unit test only if a natural seam exists (see step 3)

**Interfaces:**
- Consumes: `isOfficialClaudeProvider` (claude provider, existing).
- Produces: all three `ProviderCapability.defaultOfficialProviderId` getters return null; `_resolveDefaultClaudeProviderId` picks by `isOfficialClaudeProvider` only.

- [ ] **Step 1: Make the changes**

1. `client/lib/services/cli/cursor/capabilities/provider.dart:67`:
   `String? get defaultOfficialProviderId => 'cursor-account';` → `String? get defaultOfficialProviderId => null;`
2. `client/lib/services/cli/codex/capabilities/provider.dart:88`: same → `=> null;`
3. `client/lib/services/cli/claude/capabilities/provider.dart:99`: same → `=> null;`
4. In the same file, `_resolveDefaultClaudeProviderId` — delete the first loop:
   ```dart
    for (final provider in providers) {
      if (provider.id.trim() == 'claude-official') return provider.id;
    }
   ```
   Keep the `isOfficialClaudeProvider` loop and the sole-provider fallback; update the doc comment to drop the `claude-official` mention (e.g. "Prefer an Anthropic official provider (official category) so OAuth credentials can be linked; sole-provider fallback last.").

- [ ] **Step 2: Grep for remaining references**

Run: `grep -rn "defaultOfficialProviderId" client/lib client/test --include="*.dart" | grep -v "registry/capabilities\|=> null"`
Expected: only consumer call sites that already null-tolerate (`?? ''` / `officialProviderId(resolvedCli) ?? ''` in automation_dispatcher, session_provisional_builder, landing_draft_resolver, cursor/codex capability fallbacks). If any consumer dereferences without null handling, fix it to tolerate null the same way.

- [ ] **Step 3: Run affected suites**

Run: `flutter test test/services/cli/ test/services/ai/headless_ai_service_test.dart test/repositories/app_settings_repository_ai_features_test.dart`
Expected: PASS. (`headless_ai_service_test` and `app_settings_repository_ai_features_test` use `'claude-official'` as a config string only — they don't load the provider catalog, so they're unaffected. If one fails because it *does* depend on the row, stop and report — do not blindly rewrite test semantics.)

- [ ] **Step 4: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/cli/claude/capabilities/provider.dart \
        client/lib/services/cli/cursor/capabilities/provider.dart \
        client/lib/services/cli/codex/capabilities/provider.dart
git commit -m "Drop default official provider ids with the shared rows"
```

---

### Task 5: Full verification

- [ ] **Step 1: Analyzer**

Run: `cd /home/hhoa/git/hhoa/teampilot/client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no NEW issues in files this plan touched. Pre-existing noise (user WIP `permissionGate` error at app_shell.dart:1649, agent_runtime findings, pre-plan warnings) is out of scope.

- [ ] **Step 2: Feature suites**

Run: `flutter test test/services/provider_usage/ test/cubits/managed_provider_cubit_cli_binding_test.dart test/pages/managed_providers/managed_provider_management_page.dart test/app/app_shell_provider_usage_bootstrap_test.dart test/services/cli/`
(typo guard: the management-page path is `test/pages/managed_providers/managed_provider_management_page_test.dart`)
Expected: PASS.

- [ ] **Step 3: Full suite**

Run: `dart run tool/run_tests.dart`
Expected: same shape as the pre-plan baseline — 40 failures confined to the user's WIP areas (chat_view mocks, sidebar visibility, opencode history, team_hub loading). ZERO failures in provider_usage / managed_provider / app_provider / cli-registry suites. If a NEW failure appears in a feature-touched file, fix it and commit.

- [ ] **Step 4: Manual smoke (if a desktop environment is available)**

1. Pre-seed: create a Cursor preset entry, log in, save; delete the entry → `<teampilotRoot>/providers/cursor/cursor-mp-<id>/` disappears and the provider catalog no longer lists the row.
2. Restart the app → the sweep removes `cursor-account` / `claude-official` / `openai-official` rows and their `providers/<cli>/<shared-id>/` directories.
3. An old entry persisted with `cli:cursor-account` renders "credential not configured" (no auto-login from the old shared row).
4. Simple launch with no pinned provider launches without auto-selecting a shared row (provider falls back to sole-provider or empty).

If no desktop environment is available, skip and note it.

- [ ] **Step 5: Commit any fixes**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add -A -- client/lib/services/provider_usage client/lib/cubits client/lib/pages/managed_providers client/test/services/provider_usage client/test/cubits client/test/pages/managed_providers
git commit -m "Verify per-entry cleanup and no-compat sweep"
```
(Only if there are fixes; otherwise no commit.)
