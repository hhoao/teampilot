# Managed Provider Adaptive Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Each task must be reviewed before starting the next task.

**Goal:** Replace the flat Managed Provider form with a preset-driven adaptive editor that exposes only necessary fields by default, keeps advanced settings collapsible, and performs an optional first usage query after saving.

**Architecture:** Add a typed `ManagedProviderEditorSchema` describing provider kind, visible sections, fields, credentials, and query capability. Presets provide initial schema values while existing providers derive a compatible schema from persisted kind/adapter/endpoint. Refactor rendering into focused section widgets driven by that schema; keep persistence and secure credential handling in services/cubits.

**Tech Stack:** Flutter, flutter_bloc, Equatable, existing `Tp*` shared UI, `ManagedProviderSecretStore`, `ManagedProviderUsageCubit`, ARB localization.

## Global Constraints

- Do not change the Managed Provider JSON format or existing adapter/credential-store interfaces.
- API keys/tokens remain in secure storage; Provider JSON, request mappings, and usage snapshots remain secret-free.
- Keep editor navigation inside the HomeShell body.
- Do not branch on concrete Provider names in page rendering; use schema/capability data.
- Empty secret on edit preserves the existing secure credential.
- Generic controls belong in `client/packages/shared_ui`; reuse existing controls first.
- Keep `client/pubspec.lock` untouched; it is an existing user change.
- Add user-visible text to both ARB files and regenerate tracked localization output.
- Use TDD for each behavior and commit each independently testable task.

---

## Task 1: Add the editor schema and compatibility derivation

**Files:**

- Create `client/lib/models/managed_provider_editor_schema.dart`.
- Modify `client/lib/services/provider_usage/managed_provider_presets.dart`.
- Create `client/test/models/managed_provider_editor_schema_test.dart`.

**Interfaces:**

```dart
enum ManagedProviderEditorSection { basics, query, credentials, display, advanced }
enum ManagedProviderEditorFieldKind { text, secret, url, json, integer, toggle }

class ManagedProviderEditorField {
  const ManagedProviderEditorField({
    required this.key,
    required this.kind,
    required this.required,
    this.defaultValue,
    this.readOnly = false,
  });
  final String key;
  final ManagedProviderEditorFieldKind kind;
  final bool required;
  final String? defaultValue;
  final bool readOnly;
}

class ManagedProviderEditorSchema {
  const ManagedProviderEditorSchema({
    required this.sections,
    required this.fields,
    required this.firstQuery,
  });
  final Set<ManagedProviderEditorSection> sections;
  final List<ManagedProviderEditorField> fields;
  final bool firstQuery;
  bool hasSection(ManagedProviderEditorSection section) => sections.contains(section);
  bool hasField(String key) => fields.any((field) => field.key == key);
  static ManagedProviderEditorSchema fromProvider(ManagedProvider provider);
}
```

`fromProvider` must use `kind`, `adapterId`, and endpoint declarations only. Official Codex/Claude subscription adapters expose basics/credentials/display/advanced without custom HTTP mapping. `http-json` and custom HTTP expose query, credentials, display, and advanced. Existing non-default values keep their section available. Extend `ManagedProviderPreset` with an optional schema; DeepSeek declares API Key, dynamic currency mapping, two decimal places, and first query.

- [ ] Write tests for DeepSeek schema, custom HTTP schema, and legacy Provider derivation.
- [ ] Run `cd client && flutter test test/models/managed_provider_editor_schema_test.dart`; verify failure before implementation.
- [ ] Implement the model and preset declarations without importing Flutter UI classes.
- [ ] Run `dart format` on changed Dart files and rerun the focused test; expect all pass.
- [ ] Commit with `git commit -m "feat(managed-provider): add adaptive editor schema"`.

## Task 2: Render a schema-driven adaptive form

**Files:**

- Modify `client/lib/pages/managed_providers/managed_provider_editor_page.dart`.
- Create `client/lib/pages/managed_providers/managed_provider_editor_sections.dart`.
- Create `client/lib/pages/managed_providers/managed_provider_editor_section_shell.dart`.
- Modify `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`, and tracked generated localization files.
- Modify `client/test/pages/managed_providers/managed_provider_management_page_test.dart`.

**Interfaces:**

```dart
class ManagedProviderEditorSectionShell extends StatelessWidget {
  const ManagedProviderEditorSectionShell({
    required this.title,
    required this.subtitle,
    required this.initiallyExpanded,
    required this.child,
    this.badge,
    super.key,
  });
  final String title;
  final String? subtitle;
  final bool initiallyExpanded;
  final Widget child;
  final String? badge;
}
```

Create focused `ManagedProviderBasicsSection`, `ManagedProviderQuerySection`, `ManagedProviderCredentialsSection`, `ManagedProviderDisplaySection`, and `ManagedProviderAdvancedSection` widgets. They receive controllers and typed callbacks; the page state retains initialization, preset application, validation, save/query/delete, and navigation.

UI rules:

- Basics is always expanded and contains the searchable preset selector, name, summary, and required secret.
- Query is visible only when the schema has `query`; custom HTTP expands it by default.
- Credentials, Display, and Advanced are collapsed by default; existing non-default values expand their section and show a configured badge.
- Hide adapter id and credentialRef from normal users; if retained for migration/debugging, show them read-only under Advanced.
- Stable keys must include `managed-provider-section-basics`, `managed-provider-section-query`, `managed-provider-section-credentials`, `managed-provider-section-display`, and `managed-provider-section-advanced`.

- [ ] Add failing widget assertions for section visibility, DeepSeek’s minimal default fields, and custom HTTP expansion.
- [ ] Run the focused widget test and verify the current flat form fails those assertions.
- [ ] Move rendering into the section files and gate sections/fields through `ManagedProviderEditorSchema`; do not add Provider-name branches.
- [ ] Add localized section labels, summaries, configured badges, dynamic-currency help, and save/query copy.
- [ ] Run `dart format` and `flutter test test/pages/managed_providers/managed_provider_management_page_test.dart`; expect existing CRUD/navigation plus new hierarchy tests to pass.
- [ ] Commit with `git commit -m "feat(managed-provider): simplify adaptive editor UI"`.

## Task 3: Make credential save and first query transactional

**Files:**

- Create `client/lib/services/provider_usage/managed_provider_credential_transaction.dart`.
- Modify `client/lib/pages/managed_providers/managed_provider_editor_page.dart`.
- Do not modify `client/lib/cubits/managed_provider_usage_cubit.dart`; use its existing `Future<ProviderUsageSnapshot?> queryProvider(ManagedProvider provider)` API for the first query.
- Create `client/test/services/provider_usage/managed_provider_credential_transaction_test.dart`.
- Modify `client/test/pages/managed_providers/managed_provider_management_page_test.dart` for first-query coverage; Task 2 owns all new localization strings.

**Interface:**

```dart
class ManagedProviderCredentialTransaction {
  const ManagedProviderCredentialTransaction(this.store);
  final ManagedProviderSecretStore store;
  Future<T> run<T>({
    required String credentialRef,
    required Map<String, String> nextValues,
    required Future<T> Function() persistProvider,
  });
}
```

The transaction reads the previous scope, writes only a non-empty new secret, awaits Provider persistence, restores the previous scope on failure, and deletes a newly created ref when persistence fails. A blank secret calls `persistProvider` without touching storage. Secret failures remain localized and secret-free.

After successful new save, invoke the existing usage query once when `schema.firstQuery` is true. Query failure must not undo the saved Provider; the list shows its localized query error.

- [ ] Write failing tests for blank-secret no-op, restoring an old secret, deleting a new ref, and preserving a saved Provider after first-query failure.
- [ ] Run the two focused test files and verify failure before implementation.
- [ ] Implement the transaction and integrate it into `_save`; keep Provider serialization secret-free.
- [ ] Add the first-query success/failure widget tests.
- [ ] Run transaction and management-page tests; expect all pass.
- [ ] Commit with `git commit -m "feat(managed-provider): query and save transactionally"`.

## Task 4: Final verification and app handoff

**Files:** Modify only files required by verification failures; never modify `client/pubspec.lock`.

- [ ] Run:

```bash
cd client
dart format lib/models/managed_provider_editor_schema.dart lib/pages/managed_providers lib/services/provider_usage test/models test/pages/managed_providers test/services/provider_usage
flutter test test/models/managed_provider_editor_schema_test.dart
flutter test test/services/provider_usage/managed_provider_credential_transaction_test.dart
flutter test test/pages/managed_providers/managed_provider_management_page_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] Run `git diff --check HEAD~3..HEAD` and confirm only intentional changes plus the pre-existing `client/pubspec.lock` remain.
- [ ] Fix and commit only verification failures with `git commit -m "test(managed-provider): verify adaptive editor flow"`.
- [ ] Rebuild/restart only the executable under `/home/hhoa/git/hhoa/teampilot/.worktrees/managed-provider-usage/client`; verify the old root executable remains running.
