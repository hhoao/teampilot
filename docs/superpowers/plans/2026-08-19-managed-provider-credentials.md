# Managed Provider Credentials Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Let users enter Managed Provider API keys in the editor and persist them through the existing secure credential store while making preset display defaults visible.

**Architecture:** The editor owns a transient masked credential input and receives the app-shell `ManagedProviderSecretStore` through the existing repository-provider graph. On save it generates a stable credential reference from the provider id, writes the secret under the configured field, and persists only the reference in the provider catalog. Presets continue to provide non-secret request metadata; dynamic currencies remain response mappings with a visible fallback hint.

**Tech Stack:** Flutter, flutter_bloc RepositoryProvider, FlutterSecureStorage-backed `ManagedProviderSecretStore`, ARB localization, widget/repository tests.

---

### Task 1: Wire secure API-key entry and preset display defaults

**Files:**
- Modify: `client/lib/main.dart`
- Modify: `client/lib/services/provider_usage/managed_provider_presets.dart`
- Modify: `client/lib/pages/managed_providers/managed_provider_management_page.dart`
- Modify: `client/lib/pages/managed_providers/managed_provider_editor_page.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/managed_providers/managed_provider_management_page_test.dart`
- Test: `client/test/services/provider_usage/managed_provider_secret_store_test.dart`

- [ ] **Step 1: Write failing tests**

  Add a widget test with an in-memory secure key-value backend that enters a DeepSeek API key, saves the provider, and asserts the catalog contains only a generated credential reference while the secret store contains the API key under `apiKey`. Add assertions that a second save with an empty key preserves the existing secret and that the DeepSeek preset has `decimalPlaces: 2`.

- [ ] **Step 2: Run tests and verify they fail**

  Run `flutter test test/pages/managed_providers/managed_provider_management_page_test.dart test/services/provider_usage/managed_provider_secret_store_test.dart` from `client/`.
  Expected: the editor has no API-key field and no save path into the secure store.

- [ ] **Step 3: Expose the app-shell secret store**

  Register `shell.managedProviderSecretStore` as a `RepositoryProvider` in `main.dart`, and pass/use it from the managed-provider management/editor path without weakening the existing injection boundary. Tests must be able to inject an in-memory `SecureKeyValueStore`.

- [ ] **Step 4: Implement the editor credential flow**

  Add an obscured API Key/Token controller and field near the credential mapping section. For existing credentials, show a masked configured state and a hint that blank keeps the current value. On save, generate `managed-provider:<provider-id>` when no reference exists, write the entered value under `endpointConfig.credentialField` (default `apiKey`) through `ManagedProviderSecretStore`, and keep the model secret-free. Do not overwrite an existing secret when the new input is blank; surface a localized save error if secure storage fails.

- [ ] **Step 5: Make preset display defaults explicit**

  Set DeepSeek’s preset decimal places to `2` and add localized helper text that currency is read from the response mapping when `fieldMappings.currency` is configured. Keep fallback currency/unit fields editable for providers whose API does not return them.

- [ ] **Step 6: Run focused tests and analyzer**

  Run:
  `flutter test test/pages/managed_providers/managed_provider_management_page_test.dart test/services/provider_usage/managed_provider_secret_store_test.dart`
  and
  `flutter analyze --no-fatal-infos --no-fatal-warnings lib/main.dart lib/pages/managed_providers lib/services/provider_usage`
  Expected: all focused tests pass and analyzer exits 0.

- [ ] **Step 7: Commit the implementation**

  Commit only the credential/display implementation and tests; do not stage the pre-existing `client/pubspec.lock` modification.
