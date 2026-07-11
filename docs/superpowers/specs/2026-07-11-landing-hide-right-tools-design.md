# Landing Default-Hide Right Tools

**Date:** 2026-07-11  
**Status:** Approved  
**Related:** [Workspace Panes IDE Shell](2026-07-10-workspace-panes-ide-shell-design.md), [Workbench Center Tabs](2026-07-10-workbench-center-tabs-design.md)  
**Owner decision:** On compose landing, hide the right tools pane by default (effective-only). Allow a temporary open that does not persist. Leaving landing restores `LayoutPreferences.rightToolsVisible`.

## Problem

Compose landing is a centered prompt surface. The docked right tools pane (file tree / git / …) still follows the global `rightToolsVisible` intent (default `true`), so landing often opens with a wide inspector that competes with the compose UI. Users want landing quieter by default without losing their session-time preference.

## Goals

- Entering compose landing **defaults** the right tools pane to hidden.
- Leaving compose (selecting / opening a session) **restores** visibility from persisted `rightToolsVisible`.
- On landing, the user may **temporarily** open or close right tools without writing `rightToolsVisible`.
- Left sidebar and bottom workspace terminal behavior stay unchanged.
- Narrow overlay path follows the same effective-right rule as wide dock (landing default hide + temporary override).

## Non-goals

- Changing the persisted default of `rightToolsVisible` (still `true` for session workbench).
- Auto-hiding left sidebar or bottom terminal on landing.
- Per-workspace persisted “landing right tools” preference.
- Redesigning right-tools chrome or compose landing layout.

## Decision

**Approach B — policy + non-persisted temporary override.**

Reuse the existing `composeLanding` flag on `WorkspacePanePolicy.effective`. Landing forces right-pane effective visibility from an ephemeral override (default `false`), never from mutating intent. Session continues to honor `preferences.rightToolsVisible`.

This supersedes the v1 rule in the panes IDE shell spec that “compose ≡ session” for right-tools visibility.

## Behavior

| Context | Effective right tools | Persisted `rightToolsVisible` |
|---------|----------------------|-------------------------------|
| Session workbench | Honor intent | Unchanged by this feature |
| Enter compose landing | Hidden (`override` starts unset → treat as `false`) | Unchanged |
| Landing + user opens right tools | Shown via temporary override `true` | Unchanged |
| Landing + user closes / dismisses | Hidden via override `false` | Unchanged |
| Exit compose (`composeActive` → `false`) | Clear override; honor intent again | Unchanged |

Left / bottom: still honor intent (and narrow overlay rules) in both compose and session. “Exit compose” includes selecting a session tab, opening a history/diff/file center tab that clears compose, or any other path that sets workspace-scoped `composeActive` to `false` — not only “launch a new session.”

### Toggle & dismiss routing

All right-tools show/hide entry points must branch on compose-active:

| Entry | Compose landing | Session |
|-------|-----------------|---------|
| Visibility chip (`WorkspaceShellRightToolsVisibilityToggle`) | Flip temporary override | `setRightToolsVisible` |
| Command `toggleSecondarySidebar` / `LayoutCubit.toggleRightTools` | Same as chip | Persist flip |
| Narrow overlay dismiss (`onDismissRight`) | Set override `false` | `setRightToolsVisible(false)` |

Chip / command **pressed** state and tooltips must reflect **effective** right visibility (dock or overlay), not raw intent, while on landing.

**Global command wiring:** `LayoutCommandRegistrar` today only holds `LayoutCubit`. It must obtain workspace-scoped `composeActive` the same way other workbench commands resolve active-workspace context (e.g. via `ShortcutContext` / command context already used for session-tab shortcuts). Pass that boolean into `toggleRightTools(composeLanding: …)`. Do not persist intent from the command while compose is active.

### Clearing override

Clear the temporary override whenever the IDE shell’s workspace-scoped `composeActive` flips `true → false`. Override is **app-global ephemeral** (one slot on `LayoutCubit`), not persisted per workspace. Clear before applying session intent so the first post-compose layout pass does not flash the temporary show state.

Practical rule: `WorkspaceIdeShell` (or its parent) watches that `composeActive`; on `true → false`, call `LayoutCubit.clearLandingRightToolsOverride()`.

## Architecture

```text
ChatCubit.composeActive ──► WorkspaceIdeShell
                               │
                               ▼
              WorkspacePanePolicy.effective(
                preferences,
                viewportWidth,
                composeLanding: true/false,
                landingRightToolsOverride: bool?,  // null ⇒ false when compose
              )
                               │
                               ▼
                    dockRight / overlayRight
```

### `WorkspacePanePolicy`

Extend `effective` so that when `composeLanding == true`, the **right intent used for dock/overlay** is:

```text
rightIntent = landingRightToolsOverride ?? false
```

Left and bottom still use `preferences.sidebarVisible` / `workspaceTerminalVisible`. Narrow breakpoint logic unchanged: if narrow, sides undock and overlay eligibility follows that rightIntent.

When `composeLanding == false`, ignore `landingRightToolsOverride` entirely; use `preferences.rightToolsVisible` as today.

Update the existing unit test that asserted “compose and session visibility match in v1” to expect landing default-hide instead.

### `LayoutCubit` ephemeral state

Add non-persisted fields on `LayoutState` (not written by `LayoutRepository`):

| Field | Type | Meaning |
|-------|------|---------|
| `landingRightToolsOverride` | `bool?` | `null` = landing default hide; `true`/`false` = temporary show/hide |

API:

- `setLandingRightToolsOverride(bool visible)` — emit only; no repository save
- `clearLandingRightToolsOverride()` — set to `null`
- `toggleRightTools({required bool composeLanding})` — if compose, flip effective landing right (treat `null` as `false`); else existing persist path
- Keep `setRightToolsVisible` as the **session / persist** path; callers on landing must not use it for visibility toggles

### Shell wiring

- Pass `composeLanding` from workspace-scoped chat compose state into `WorkspacePanePolicy.effective` / snapshot sync (today the shell never passes it).
- Pass `landingRightToolsOverride` from `LayoutCubit.state`.
- Rebuild / `_requestSync` when either compose-active or override changes (extend `listenWhen` / relevant-change checks beyond prefs-only).
- Overlay dismiss and visibility chip use the branching table above.

### Spec delta (related docs)

- In `2026-07-10-workspace-panes-ide-shell-design.md`, replace the “Compose landing vs session” table row that says compose honors the same intent with: compose **defaults right tools hidden**; temporary override; left/bottom unchanged. Point here for full rules.
- In `2026-07-10-workbench-center-tabs-design.md`, amend the note that right tools “stay available” during compose: they remain **reachable** (temporary reveal + center-tab openers), but are **not shown by default** on landing.

## Testing

| Case | Expect |
|------|--------|
| Policy wide + compose + override `null` | `dockRight == false` even if prefs right visible |
| Policy wide + compose + override `true` | `dockRight == true` |
| Policy wide + session | ignores override; honors prefs |
| Policy narrow + compose + override `null` | no right overlay eligibility |
| Policy narrow + compose + override `true` | `overlayRight == true` |
| Cubit: landing toggle does not change saved prefs | repository / preferences.rightToolsVisible stable |
| Cubit: clear override on request | override → `null` |
| Widget/smoke: open workspace on compose landing | right tools panel not shown by default when prefs say visible |
| Widget: open tools on landing then select session | panel follows prefs after compose clears |

## Risks / notes

- File tree / git can still open center tabs **after** the user temporarily reveals right tools on landing; default-hide does not remove that capability, only the default chrome.
- Shortcut and chip must share one toggle path so landing does not accidentally persist intent.
- Existing smoke tests that assume right tools visible on first workspace paint need updating for compose-first entry.
