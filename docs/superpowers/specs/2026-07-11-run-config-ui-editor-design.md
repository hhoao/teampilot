# Run Config UI Editor

**Date:** 2026-07-11  
**Status:** Ready for planning  
**Related:** [Workspace Run Platform](2026-07-11-workspace-run-platform-design.md)  
**Owner decision:** Prefer best architecture / UX / extensibility over workload or backward compatibility. Users configure runs **only through UI** (never guided to edit `.teampilot/launch.json`). Toolbar stays minimal; config management uses a schema-driven Edit Configurations dialog (IDEA-like dual pane) opened from the config dropdown.

## Problem

The workspace Run platform already persists configs in per-folder `.teampilot/launch.json` and exposes a title-bar Run toolbar, but:

- Build / Debug glyphs are always visible as disabled placeholders.
- A More menu exposes “Open launch.json” and secondary actions, pushing power-user file editing.
- There is no structured UI to create, edit, or delete launch configurations; accepting discover or opening JSON is the only path.

Users expect an IDEA-like flow: pick a config in the dropdown, edit/delete inline, add from the footer, and manage configs in a proper dialog—without touching JSON.

## Goals

- Toolbar chrome: **config dropdown + Run/Stop only**; Build/Debug appear **only when** the selected launch type’s `kinds` include that capability.
- Remove the More menu; no “Open launch.json” (or any user-facing path to the raw file).
- Dropdown rows: primary tap selects; **Edit** and **Delete** on the right (`AppIconButton`); footer **Add configuration…**.
- **Edit Configurations** dialog: left list + right **schema-driven** form; Add / Edit / adopt-recommendation open it.
- Persistence remains `.teampilot/launch.json` via `LaunchConfigStore` / `RunCubit`; UI never exposes the path as an editing surface.
- Extensibility: new launch types contribute `configurationSchema`; the form renderer adapts without hardcoding type fields in the dialog (built-in `process` uses its existing schema).
- Runtime adapter choice options remain reachable via **toolbar compact selectors** (not More, not editor-only).

## Non-goals

- Full Debug / Build execution (only visibility gating for future `kinds`).
- VS Code `.vscode/launch.json` import/compat.
- Per-type custom form widgets beyond generic schema→control mapping (password / path pickers may come later via schema `ui` hints).
- Replacing discover/recommendations (they remain; adopting them goes through the editor / save path, not JSON).
- Changing Run session execution, compounds runtime, or Launch Adapter protocol (except store/cubit CRUD needed for UI).
- Compound create/edit/delete UI (compounds remain runnable from the dropdown only).

## Decision

**Approach: Dropdown quick actions + schema-driven dual-pane editor.**

```text
RunToolbar
  Config dropdown (SidebarActionMenu)
    row → select | Edit → editor | Delete → confirm → cubit.delete
    footer → Add → editor (new draft)
  Run/Stop (kinds-gated Debug/Build later)
       ↓
RunConfigEditorDialog (AppDialog)
  left: configurations only (grouped by folder when multi-root)
  right: LaunchConfigSchemaForm(type.schema)
       ↓
RunCubit.save / delete / create draft
       ↓
LaunchConfigStore.upsert / delete → .teampilot/launch.json
```

Rejected alternatives:

| Alternative | Why not |
|-------------|---------|
| Light single-config Orca form only | Weak multi-config management; hardcodes `process` fields; poor extension fit |
| Settings page only (no dialog from dropdown) | Extra navigation for the common edit path |
| Keep “Open launch.json” as primary edit | Conflicts with UI-only configuration goal |
| Always show disabled Build/Debug | Noise; contradicts “appear when capability exists” |

## UI

### Toolbar

| Control | When shown |
|---------|------------|
| Config dropdown | Always (when Run chrome is mounted for an open workspace tab) |
| Run / Stop | Always in chrome; Run enabled when a runnable selection exists |
| Debug | Only if selected type `kinds` contains `debug` |
| Build | Only if selected type `kinds` contains `build` (or equivalent reserved kind) |
| More | **Removed** |

`process` (and typical v1 types) advertise `kinds: ['run']` only → no Debug/Build buttons.

### Config dropdown

- **Saved configs:** icon + name; trailing Edit + Delete. Row body selects. Edit/Delete must not trigger select (stop propagation).
- **Recommendations:** shown as suggested; Edit/Adopt opens editor prefilled; **Delete control hidden** (not a no-op button).
- **Compounds:** selectable to **run** only in this feature’s MVP. No compound Edit/Delete in the dropdown and no compound authoring in the editor left pane yet (runtime compounds unchanged). Compound CRUD is explicitly **out of scope** here.
- **Adapter `isAction` entries:** remain in the dropdown (host picker → `configureAction`); unchanged from the Run platform.
- **Footer:** divider + **Add configuration…** → editor with new draft (pick `type` from registry; default `process`).
- No “Open launch.json”. Discover refresh stays on `load` / editor open (no menu item required).

### Runtime dynamic options (after More removal)

Adapter **choice** options (e.g. device) are **run-time** controls, not editor-only.

When the selected configuration exposes choice options via `RunCubit` / adapter:

- Show **compact choice dropdown(s)** in the toolbar **between** the config dropdown and Run/Stop (IDEA-like device picker).
- Changing a value calls `setOption` as today (applied into extras at run).
- Do **not** bury these only in the Edit Configurations dialog (that would break change-then-run without reopening the editor).

Editor may still show the same fields when editing a type that declares them; toolbar compact selectors are the primary run-time surface.
### Edit Configurations dialog

**Shell:** Large `AppDialog` (settings-dialog style): left nav + right form; footer Cancel / Apply / OK.

**Open:**

| Entry | Focus |
|-------|--------|
| Dropdown Edit | That configuration |
| Dropdown Add | New draft after type (and folder, if multi-root) choice |
| Adopt recommendation | Prefill from recommendation; Save writes owning folder |

**Left pane:**

- Configurations grouped by folder when multi-root.
- Actions: Add (type picker), Delete. **Duplicate is deferred** (not MVP).
- Compounds are **not** listed for editing in this MVP (run from dropdown only).

**Right pane:**

- Common: Name; Type (read-only after create).
- Remaining fields from `LaunchTypeContribution.configurationSchema` (or built-in `ProcessLaunchSchema.configurationSchema`).
- Generic mapping (v1):
  - `string` → text field (monospace for command-like props when name is `command` / `cwd` or schema hint)
  - `array` of `string` → single line or whitespace-separated → `List<String>`
  - `object` with string values → `KEY=VALUE` lines → `Map<String,String>`
  - `boolean` → switch
- Validation: schema + type `validate`; inline errors; no disk write until valid Apply/OK.
- Apply: save, keep dialog open. OK: save and close. Cancel: discard unapplied edits.

**Multi-folder create:** prompt or dropdown for target `WorkspaceFolder` before draft is bound.

**Dirty state:** If the user selects another left-pane item (or closes) with unapplied edits, prompt to Apply / Discard / Cancel navigation. Do not silently discard or auto-apply.

## Data and API

### LaunchConfigStore

| Method | Behavior |
|--------|----------|
| `upsertConfiguration` | Existing |
| `deleteConfiguration({folder, id})` | **New** — remove from document, write back |

Compound store APIs are **not** required for this feature MVP.
### RunCubit / RunPlatform

| Method | Behavior |
|--------|----------|
| `saveConfiguration(owned)` | Validate → persist → `load()` → select saved key |
| `deleteConfiguration(owned)` | If a session is running for this config: **confirm stop-then-delete** (single product path; not silent refuse). On confirm: stop → delete → `load()`; fix selection if deleted was selected. If not running: confirm delete → delete → `load()`. |
| `createConfiguration({folder, type})` | Return in-memory draft (not persisted until save) |
| `acceptRecommendation` | **Always** open the editor prefilled; user Save persists (same as `saveConfiguration`). No silent auto-write bypass. |

Dynamic adapter **choice options** use the toolbar compact selectors described above (`setOption`), not a More menu.
## Error handling

| Scenario | Behavior |
|----------|----------|
| Form validation failure | Stay in dialog; show field/top errors |
| Persist IO failure | Keep draft; l10n error (dialog or snackbar) |
| Delete while running | Confirm **stop then delete**; cancel leaves session and config |
| Type unavailable on target | Selectable; Run disabled; editor still editable with availability hint |
| Unknown schema property types | Skip or treat as string; log diagnostic |
| Schema failure at Run | Block Run; surface errors; offer **Edit configuration** (not open launch.json) |
## Testing

- Store: `deleteConfiguration` round-trip; upsert+delete leaves document consistent.
- Cubit: save / delete / create-draft→save updates list and selection; delete running path.
- Toolbar: no More/Build/Debug for `process`; Edit/Delete icons do not select; Add opens editor.
- Editor: process schema fields render and validate; Apply/OK/Cancel; multi-folder create picks folder.
- Regression: Run/Stop, compounds run, discover list still loads.

## Expected code areas

| Area | Path (expected) |
|------|-----------------|
| Editor dialog | `client/lib/widgets/run/run_config_editor_dialog.dart` |
| Schema form | `client/lib/widgets/run/launch_config_schema_form.dart` |
| Toolbar | `client/lib/widgets/run/run_toolbar.dart` |
| Store / platform / cubit | `launch_config_store.dart`, `run_platform.dart`, `run_cubit.dart` |
| l10n | `app_en.arb` / `app_zh.arb` (`runEditConfiguration`, `runAddConfiguration`, `runDeleteConfiguration`, …) |
| Tests | `test/widgets/run/`, `test/cubits/run_cubit_*`, `test/services/run/launch_config_store_*` |

## Relationship to prior Run platform spec

This spec **extends** [2026-07-11-workspace-run-platform-design.md](2026-07-11-workspace-run-platform-design.md):

- Retains launch.json as the on-disk format and Run execution model.
- **Supersedes** toolbar details that assumed More menu, open-launch.json, and always-visible disabled Build/Debug.
- Adds UI-first CRUD and schema-driven editing as the supported configuration path.
