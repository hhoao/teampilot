# Managed Provider Official Login and Usage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Official Codex/Claude Managed Providers can sign in on the editor, list cards stay readable, and usage queries call the same official HTTP endpoints as cc-switch/Orca.

**Architecture:** Reuse `ProviderCredentialActionBar` against the existing official CLI provider rows. Query-time auth reads known credential files (not the CLI provider list). New `OfficialSubscriptionClient` implementations parse Claude `/api/oauth/usage` and Codex `wham/usage` into `OfficialSubscriptionWindow`.

**Tech Stack:** Flutter/Dart, existing Managed Provider adapters, `ProviderUsageHttpClient`, AppProviderCubit.

## Global Constraints

- Official secrets never enter Managed Provider JSON or SecretStore.
- Query-time auth must not scan all `AppProviderConfig` rows.
- l10n only in `app_en.arb` / `app_zh.arb`.
- Work in `.worktrees/managed-provider-usage`. Do not commit unless asked.

---

### Task 1: Official CLI binding

**Files:**
- Create: `client/lib/services/provider_usage/official_managed_provider_binding.dart`
- Test: `client/test/services/provider_usage/official_managed_provider_binding_test.dart`

- [ ] Map `official-codex-subscription` → Codex / `openai-official`
- [ ] Map `official-claude-subscription` → Claude / `claude-official`
- [ ] `ensureOfficialAppProvider` upserts the preset template when missing

### Task 2: List card layout

**Files:**
- Modify: `client/lib/pages/managed_providers/managed_provider_list.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`, `client/lib/l10n/l10n_extensions.dart`
- Test: `client/test/pages/managed_providers/managed_provider_management_page_test.dart`

- [ ] Subtitle is localized kind · provider name
- [ ] Actions stay in a non-wrapping Row

### Task 3: Editor login bar

**Files:**
- Create: `client/lib/pages/managed_providers/managed_provider_official_credentials.dart`
- Modify: `client/lib/pages/managed_providers/managed_provider_editor_page.dart`
- Test: management page widget tests

- [ ] Official presets show `ProviderCredentialActionBar`
- [ ] DeepSeek still shows the API key field
- [ ] Official credentials section starts expanded

### Task 4: Auth readers

**Files:**
- Create: `client/lib/services/provider_usage/adapters/claude_official_subscription_auth.dart`
- Create: `client/lib/services/provider_usage/adapters/codex_official_subscription_auth.dart`
- Test: `client/test/services/provider_usage/official_subscription_auth_test.dart`

- [ ] Isolated TeamPilot path wins over `~/.claude` / `~/.codex`
- [ ] Missing token → `missingCredential` without leaking secrets

### Task 5: HTTP clients

**Files:**
- Create: `client/lib/services/provider_usage/adapters/claude_official_subscription_client.dart`
- Create: `client/lib/services/provider_usage/adapters/codex_official_subscription_client.dart`
- Test: `client/test/services/provider_usage/official_subscription_client_test.dart`

- [ ] Claude `/api/oauth/usage` windows
- [ ] Codex `wham/usage` primary/secondary windows
- [ ] 401 → `authenticationFailed`

### Task 6: Wire production + copy

**Files:**
- Modify: `client/lib/app/app_shell.dart`
- Modify: Codex/Claude preset hints in arb files

- [ ] Production registry uses real readers/clients
- [ ] Hint copy says sign in on this page
