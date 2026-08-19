# Managed Provider Presets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Add extensible quick-create presets for Codex, Claude Code, DeepSeek, and OpenCode to the Managed Provider editor.

**Architecture:** Presets are immutable definitions in a dedicated provider-usage preset registry, each producing a complete `ManagedProvider` draft without secrets. The editor exposes the registry only for new providers and copies the selected draft into its existing controllers; persistence, credential storage, and usage adapters remain unchanged.

**Tech Stack:** Flutter, Dart immutable models, flutter_bloc, existing `http-json` and official subscription adapters, ARB localization, widget tests.

---

### Task 1: Add preset definitions and editor quick-create control

**Files:**
- Create: `client/lib/services/provider_usage/managed_provider_presets.dart`
- Modify: `client/lib/pages/managed_providers/managed_provider_editor_page.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Test: `client/test/services/provider_usage/managed_provider_presets_test.dart`
- Test: `client/test/pages/managed_providers/managed_provider_management_page_test.dart`

- [ ] **Step 1: Write failing tests**

  Add tests asserting the registry exposes stable IDs `codex`, `claude-code`, `deepseek`, and `opencode`; Codex/Claude use subscription adapters; DeepSeek uses `http-json` with `https://api.deepseek.com/user/balance`, `GET`, `$.balance_infos`, bearer credential mapping, and `$.total_balance`; OpenCode is a custom HTTP template with no fabricated endpoint. Add a widget test that selecting the DeepSeek preset fills the editor name and endpoint while leaving credentials for the user to supply.

- [ ] **Step 2: Run tests and verify they fail**

  Run `flutter test test/services/provider_usage/managed_provider_presets_test.dart test/pages/managed_providers/managed_provider_management_page_test.dart` from `client/`.
  Expected: preset registry and the editor preset control are missing.

- [ ] **Step 3: Implement immutable preset definitions**

  Add `ManagedProviderPreset` with stable `id`, localization key/id, and `ManagedProvider template`; expose `builtInManagedProviderPresets` and lookup by id. Define only safe non-secret defaults. DeepSeek must use the official API balance shape; Codex and Claude Code must point at the existing official subscription adapter boundaries; OpenCode must be explicitly marked as requiring a provider-specific endpoint.

- [ ] **Step 4: Add the editor control and localization**

  On new-provider forms only, render a quick preset select before the identity section. Applying a preset copies all template fields into the existing controllers/state, clears any prior draft error, and never writes credentials. Editing an existing provider hides the selector. Add English and Simplified Chinese labels/hints for the selector and four presets.

- [ ] **Step 5: Run focused tests and analyzer**

  Run:
  `flutter test test/services/provider_usage/managed_provider_presets_test.dart test/pages/managed_providers/managed_provider_management_page_test.dart`
  and
  `flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/provider_usage lib/pages/managed_providers`
  Expected: all focused tests pass and analyzer exits 0.

- [ ] **Step 6: Commit the implementation**

  Commit the preset model, editor, localization, and tests. Do not stage the pre-existing `client/pubspec.lock` modification.
