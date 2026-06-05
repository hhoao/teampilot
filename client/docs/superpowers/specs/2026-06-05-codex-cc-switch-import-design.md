# Codex + CC Switch Import Design

**Date:** 2026-06-05  
**Status:** Approved (user confirmed scheme A)  
**Scope:** TeamPilot `client/` — Codex provider import, catalog storage, and provision to per-provider `CODEX_HOME`.

## Problem

Users who manage Codex via CC Switch (`cc-switch` desktop app) see imported TeamPilot providers that do not match `~/.codex/config.toml`.

Typical symptoms:

- `baseUrl` shows `https://api.deepseek.com` while live `config.toml` has `http://127.0.0.1:15721/v1`.
- `configToml` in `providers.json` is a short template (projects/features/MCP missing).
- Provider `id` is a CC Switch UUID, not `default`.

This is expected under CC Switch’s **two-layer config** model, not a regex bug in TeamPilot.

## CC Switch context (external)

| Layer | Location | Contents |
|-------|----------|----------|
| **Catalog (stored)** | `~/.cc-switch/cc-switch.db` → `providers.settings_config` | JSON: `{ "auth": {...}, "config": "<TOML>" }`. TOML uses **upstream** `base_url` (e.g. DeepSeek official URL). |
| **Runtime (live)** | `~/.codex/auth.json`, `~/.codex/config.toml` | What Codex CLI reads. Under **proxy takeover**, live TOML uses local proxy URL + `PROXY_MANAGED` token placeholders. |

CC Switch UI copy (`configTomlStorageHint`): *proxy takeover shows stored config, not live config.toml.*

Current provider id: `~/.cc-switch/config.json` → `current_provider_codex`, else DB `providers.is_current = 1` for `app_type = 'codex'`.

Proxy takeover signals (any of):

- `auth.json`: `OPENAI_API_KEY == "PROXY_MANAGED"`
- `config.toml`: `experimental_bearer_token = "PROXY_MANAGED"`
- Live `base_url` points at local proxy (e.g. `127.0.0.1:15721`)

TeamPilot today (`ProviderImportService._importCodex`):

1. Import live → `id: default`, full file in `configToml` (if read succeeds).
2. Import all CC Switch rows → UUID ids, `configToml` from DB `settings_config` (upstream template).
3. Same id: CC Switch overwrites live; different ids: both coexist; team may bind UUID while runtime is live.

## Goals

1. **Imported “current” CC Switch provider** matches what Codex actually runs (`~/.codex/*` when that provider is active).
2. Preserve **catalog** data (name, icon, category, upstream TOML, real API keys, `meta.apiFormat`, etc.).
3. Keep TeamPilot’s **per-provider `CODEX_HOME`** provision model (no global-only `~/.codex` coupling).
4. Architecture extensible to future catalog sources and runtime resolvers.

## Non-goals

- Embedding or invoking CC Switch Tauri APIs from TeamPilot.
- Reimplementing CC Switch proxy routing inside TeamPilot.
- Migrating historical `providers.json` entries automatically beyond re-import behavior (users can re-import).

## Chosen approach: Runtime + Catalog (Scheme A)

### Conceptual pipeline

```text
CatalogSource(s)     cc-switch.db, (future: presets-only, manual)
        │
        ▼
RuntimeResolver      ~/.codex/* + current_provider_codex + takeover detection
        │
        ▼
EffectiveConfig      AppProviderConfig per id
        │
        ▼
Provisioner          ToolConfigGenerator → providers/codex/{id}/config.toml
```

### Data model (`AppProviderConfig.config`)

| Key | Type | Meaning |
|-----|------|---------|
| `configToml` | `string` | **Runtime / effective** TOML written to `CODEX_HOME` (prefer live when provider is current). |
| `upstreamConfigToml` | `string` (new, optional) | CC Switch stored TOML from `settings_config.config` (upstream profile). |
| `auth` | `map` | API keys; merge live + DB (real key from DB when live uses `PROXY_MANAGED`). |
| `meta` | `map` | Pass-through from CC Switch (`apiFormat`, `codexChatReasoning`, …). |

Additional `meta` keys written by TeamPilot on import:

| Key | Meaning |
|-----|---------|
| `ccSwitchProviderId` | Same as provider `id` when sourced from CC Switch. |
| `proxyTakeover` | `true` when takeover detected at import time. |
| `importSources` | e.g. `["cc-switch", "live"]` for debugging. |

Top-level fields:

- `baseUrl`, `defaultModel` — parsed from **`configToml`** (runtime), not from upstream template alone.
- `apiKey` — from merged `auth`; prefer real key from catalog when live is placeholder.

### Import algorithm (`_importCodex`)

**Step 1 — Read runtime snapshot**

- Paths: `{home}/.codex/config.toml`, `{home}/.codex/auth.json`.
- `liveToml`, `liveAuth`, `takeover = detectProxyTakeover(liveToml, liveAuth)`.

**Step 2 — Resolve current CC Switch provider id**

- Read `{home}/.cc-switch/config.json` → `current_provider_codex`.
- If missing/invalid: SQL `SELECT id FROM providers WHERE app_type = 'codex' AND is_current = 1 LIMIT 1`.

**Step 3 — Import CC Switch catalog rows**

For each row in `cc-switch.db` (`app_type = 'codex'`):

- `catalogToml` = `settings_config.config` (fallback keys: `configToml`, `config_toml` — keep existing fallbacks).
- `catalogAuth` = `settings_config.auth`.
- `meta` = row `meta` + `ccSwitchProviderId`.

If `row.id == currentProviderId`:

- `configToml` = `liveToml` if non-empty, else `catalogToml`.
- `upstreamConfigToml` = `catalogToml`.
- `auth` = merge: use `catalogAuth` API key when live has `PROXY_MANAGED`.
- `meta.proxyTakeover` = `takeover`.
- Parse `baseUrl` / `defaultModel` from effective `configToml`.

Else (non-current catalog entry):

- `configToml` = `catalogToml` (archival; for switching reference).
- `upstreamConfigToml` optional (same as catalog).
- No live overlay.

**Step 4 — `default` provider (live snapshot)**

- Always upsert `id: default` from live files when `config.toml` or `auth.json` exists.
- `configToml` = full live content; mark `meta.importSources` includes `live`.
- If `default` duplicates current UUID semantically, both may exist: `default` = raw runtime mirror; UUID = team-facing CC Switch identity. Document in UI that members should select the CC Switch-named provider, not `default`, when using CC Switch.

**Step 5 — Merge / save**

- Merge order unchanged: live-derived entries first, then CC Switch rows by id (overwrites same id only).
- Do not drop non-current UUID providers.

### Provision / write-back (`ToolConfigGenerator`, `AppProviderRepository`)

- `buildCodexConfigToml`: continue to prefer explicit `config['configToml']` verbatim.
- **Guard:** when saving providers, do not regenerate TOML from empty `baseUrl` if `configToml` is already non-empty (prevents truncating full live files).
- Launch path: selected provider’s `CODEX_HOME` receives **runtime** `configToml` → under takeover, Codex talks to local proxy (`127.0.0.1:15721`), consistent with CC Switch.

### UI (minimal for v1)

- Base URL field shows value parsed from runtime `configToml`.
- Optional: subtitle when `meta.proxyTakeover == true` — “Local proxy (CC Switch)” (l10n).
- Advanced JSON: expose `upstreamConfigToml` for power users (no dedicated editor required in v1).

### Takeover detection (`detectProxyTakeover`)

Return `true` if any:

1. `liveAuth['OPENAI_API_KEY'] == 'PROXY_MANAGED'`
2. `liveToml` contains `experimental_bearer_token = "PROXY_MANAGED"`
3. First `base_url` in `liveToml` matches localhost proxy pattern (`127.0.0.1`, `localhost`, configurable port default `15721`)

## Module layout (implementation hint)

| Unit | Responsibility |
|------|----------------|
| `codex_runtime_resolver.dart` | Read live `~/.codex`, detect takeover, parse current id from `config.json` + DB |
| `cc_switch_catalog_source.dart` | Read `cc-switch.db` rows into catalog DTOs |
| `codex_effective_config_builder.dart` | Merge catalog + runtime → `AppProviderConfig` |
| `provider_import_service.dart` | Orchestrate `_importCodex` using above |

Keep files under `client/lib/services/provider/`; tests under `client/test/services/provider/`.

## Testing

| Case | Expect |
|------|--------|
| Takeover + current UUID | `configToml` contains `127.0.0.1:15721`, `upstreamConfigToml` contains `api.deepseek.com` |
| Takeover + non-current UUID | `configToml` = catalog only (upstream URL) |
| No takeover, normal switch | Current provider `configToml` ≈ catalog; live matches upstream |
| Live `default` | Full live file preserved including `[projects]`, `[features]`, `[mcp_servers]` |
| `PROXY_MANAGED` + catalog auth | `apiKey` from catalog, not placeholder |
| Save round-trip | Saving provider does not shorten existing `configToml` |

Fixtures: minimal `cc-switch.db` (sqlite in temp dir), temp `~/.codex` + `~/.cc-switch/config.json`.

## Error handling

- Missing `cc-switch.db`: live-only import (`default` + any `auth-*.json` profiles).
- Missing live files: catalog-only import (current behavior for UUID rows).
- SQLite / JSON parse errors: skip CC Switch source, log via `AppLogger`, continue with live.
- Invalid TOML in live: still store raw string in `configToml`; `validateCodexToml` on write-back surfaces error.

## Extensibility

- **New catalog source:** implement `CatalogSource` interface; plug into `_importCodex` beside CC Switch.
- **New runtime signal:** extend `detectProxyTakeover` without changing merge rules.
- **Bypass proxy (future):** launch mode could use `upstreamConfigToml` + real `auth` while `proxyTakeover` documents intent; out of v1 scope.

## References

- TeamPilot: `client/lib/services/provider/provider_import_service.dart`
- TeamPilot: `client/lib/services/provider/tool_config_generator.dart`
- CC Switch: `src-tauri/src/services/proxy.rs`, `src-tauri/src/codex_config.rs`, `src-tauri/src/settings.rs` (`current_provider_codex`)
