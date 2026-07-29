# Run toolbar default launch selection + placeholder label

**Date:** 2026-07-30  
**Status:** Approved (spec review)  
**Product:** TeamPilot (`client/`)  
**Scope:** Run toolbar config dropdown (`RunToolbarConfigDropdown` / `RunCubit`)

## Problem

After loading workspace launch configs, the Run toolbar dropdown leaves `selectedKey` empty and shows the placeholder「选择配置」/ “Select configuration”, even when configurations (or compounds) already exist. Users expect a ready-to-run default: last used when possible, otherwise the first real entry.

## Goals

1. On load, auto-select in this order:
   1. Persisted last `selectedKey` for this workspace, if it still resolves to a config or compound
   2. Else first configuration
   3. Else first compound
   4. Else remain unselected (placeholder only)
2. Persist last selection across app restarts, keyed by `workspaceId`.
3. Rename empty-state trigger label: 中文「启动」/ English「Launch」.

## Non-goals

- Auto-selecting discover recommendations as a default fallback.
- Writing selection into `.teampilot/launch.json` (repo-facing config).
- Changing Run / Stop / Debug button labels (`runAction` stays「Run」).
- Multi-folder “which folder’s first config” policy beyond current list order from `listConfigurations` / `listCompounds`.
- Remembering option values / launch options alongside selection.

## Decisions

| Topic | Choice | Why |
|-------|--------|-----|
| Persistence | App-data `ui/run-ui-prefs.json` keyed by `workspaceId` (mirror `WorktreeUiPrefsStore`) | Cross-restart; does not pollute committed `launch.json` |
| Fallback | Config first, else compound; never auto-pick recommendations | Owner choice 3; recommendations are drafts/suggestions |
| Remember recommendations | Yes, if the user **manually** selects one | Same `select()` write path |
| Placeholder copy | Toolbar empty trigger: `runSelectConfiguration` →「启动」/「Launch」. Editor `_draft == null` keeps「选择配置」via a **separate** key (e.g. leave old wording on a new `runEditorSelectConfiguration`, or keep editor on a dedicated string) | Owner request for toolbar only; `run_config_editor_dialog` currently shares the same key and must not show「启动」 |
| Apply timing | After every `load()` that refreshes config/compound lists, resolve from **prefs `selectedKey`** (not “only when memory `selectedKey` is null”), then `select` if non-null | Ensures delete / save reload paths re-fall back when the remembered key is stale |

## Architecture

```
WorkspaceRunRegistry.cubitFor(workspaceId, …)
  → RunCubit(workspaceId, prefsStore, …)
  → load()
       listConfigurations / listCompounds
       → resolveDefaultSelection(prefs, lists)
       → select(key) when resolved
  → select(key)
       emit selectedKey
       prefsStore.save(workspaceId, selectedKey)
```

### Units

| Unit | Role |
|------|------|
| `RunUiPrefsStore` | Read/write `{ workspaceId: { selectedKey: string } }` at `ui/run-ui-prefs.json` via `AppStorage.paths` (new path getter, same family as `worktreeUiPrefsJson`) |
| `RunCubit` | Accept `workspaceId` + optional prefs store (injectable for tests); after load, apply default selection; on successful `select`, persist; after delete of current selection, re-apply default resolution and persist |
| `WorkspaceRunRegistry` | Pass `workspaceId` (already known) into `RunCubit` construction |
| l10n | Toolbar: `runSelectConfiguration` →「启动」/「Launch」. Editor empty draft: new key retaining「选择配置」/「Select configuration」, switch `run_config_editor_dialog` to it |

### Default resolution (pure helper, unit-testable)

Inputs: optional `persistedKey`, `configurations`, `compounds`.

```
if persistedKey matches a config or compound selectionKey → that key
else if configurations.isNotEmpty → configurations.first.selectionKey
else if compounds.isNotEmpty → compounds.first.selectionKey
else → null
```

Recommendations are **not** inputs to this helper. If `persistedKey` only matches a recommendation that is not yet loaded, treat as missing and fall through (user can re-select after discover; optional later: re-check after `refreshDiscover` only when still unselected and persisted key now matches a recommendation — **out of scope** for v1; v1 only restores keys present in configs/compounds at load time).

### Delete / reload behavior

- Any path that calls `load()` (initial open, `deleteConfiguration`, `saveConfiguration`, etc.) re-runs default resolution from prefs + fresh lists. Stale prefs key → first config/compound (or null).
- `deleteConfiguration` today clears selection when the deleted key was selected. Change: after reload, resolve + `select` (or clear prefs when null) instead of leaving empty while other configs remain.
- Creating/saving a new config that becomes selected already calls `select` — persistence rides that path.
- v1: a manually selected recommendation is written to prefs, but the next `load()` that only sees configs/compounds will **not** restore that recommendation key (same as discover-after-load limitation).

### Wiring

- Prefs IO failures: treat as no persisted key (load continues; do not block Run UI).
- Save failures: log via existing diagnostics style if any; selection still applies in memory.

## UI behavior

| State | Trigger label |
|-------|----------------|
| Selected config / compound / recommendation | Existing name / suggested label |
| Nothing selectable | `runSelectConfiguration` →「启动」/「Launch」 |

Empty list: trigger still shows「启动」; menu keeps Add / Configure entries.

## Testing

1. **Unit** `run_ui_prefs_store_test.dart` — round-trip save/load per workspaceId; missing file → empty.
2. **Unit** default resolver — persisted hit; stale key → first config; no configs → first compound; empty → null; recommendation-only list does not auto-pick.
3. **Cubit** `run_cubit` (extend existing) — `load()` selects first config when no prefs; restores prefs when key exists; `select` writes prefs; delete selected re-falls back.
4. **Optional widget** — dropdown shows config name after load instead of placeholder when configs exist (existing `run_toolbar_test` harness).

## Out of scope follow-ups

- Re-bind persisted recommendation keys after discover completes.
- Per-folder last selection when multi-root workspaces need finer memory.
- Syncing selection into `launch.json` for VS Code parity files.
