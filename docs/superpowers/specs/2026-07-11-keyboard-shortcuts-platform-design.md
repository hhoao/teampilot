# Keyboard Shortcuts Platform

**Date:** 2026-07-11  
**Status:** Implemented (all v1 plan tasks landed on `feat/keyboard-shortcuts-platform`; `flutter analyze` clean of new issues, `flutter test --exclude-tags integration` green)  
**Owner decision:** Full platform (rebinding UI + conflict detection + cheatsheet); VS Code/Cursor-style defaults; terminal whitelist passthrough; no backward compatibility with the compose-only shortcut enum.

## Problem

TeamPilot has no app-wide shortcut system. Only compose Enter / Mod+Enter exists (`KeyboardShortcutAction` + `KeyboardShortcutBindings`), while users need IDE-grade navigation (workspace tabs, session tabs), zoom, pane toggles, and tab lifecycle — including while a PTY holds focus. Ad-hoc `HardwareKeyboard` / `Shortcuts` widgets would fork matching logic and block a settings page.

## Goals

- One **command** catalog and one **keybinding** layer for all keyboard-driven app actions (including compose).
- Root-level dispatch that works when focus is in terminal, editor, compose, or chrome.
- User-rebindable bindings with conflict detection, reset, and import/export.
- VS Code / Cursor-shaped defaults; Mod = ⌘ on macOS, Ctrl elsewhere.
- Easy extension: new feature = catalog entry + handler registration; settings UI picks it up automatically.

## Non-goals (v1)

- Command palette (`Mod+Shift+P`) — architecture leaves a hook; UI deferred.
- Per-workspace or per-CLI binding profiles.
- Chord sequences (press A then B); only simultaneous modifiers + key.
- Remapping OS / IME reserved keys.
- Touch-only Android gesture equivalents (physical keyboard on Android is in scope).

## Decision

**Command registry + keybinding store + root `HardwareKeyboard` dispatcher.**

Delete the compose-only `KeyboardShortcutAction` enum and fold compose into the same catalog. Do not run a parallel Flutter `Shortcuts`/`Actions` tree for app commands (local widgets may still use focus-node key handlers that *call* the shared matcher).

```text
KeyDownEvent
  → ShortcutDispatcher (app root HardwareKeyboard handler)
      → ShortcutContext.from(focus + route + cubit state)
      → KeybindingResolver.match(event, effectiveBindings, context)
          → if match && whenSatisfied && (not inTerminal || terminalPassthrough)
              → CommandBus.invoke(commandId)
              → handled (do not forward to PTY / text field)
          → else ignored
```

## Architecture

### Layers

| Layer | Responsibility | Location (proposed) |
|-------|----------------|---------------------|
| Command catalog | Stable ids, category, defaults, when, passthrough, l10n keys | `services/commands/command_catalog.dart` |
| Command bus | Register/unregister handlers; invoke by id | `services/commands/command_bus.dart` |
| Key chord model | Portable chord (`key` + `mod`/`shift`/`alt`/`ctrl`); platform → `SingleActivator` | `services/commands/key_chord.dart` |
| Keybinding store | Load/save user overrides; merge with defaults; conflict scan | `repositories/keybinding_repository.dart` |
| Shortcut cubit | Effective map for UI + dispatcher; rebind/reset/import | `cubits/shortcut_cubit.dart` |
| Context | `inTerminal`, `inCompose`, `hasWorkspace`, `hasSessionTab`, … | `services/commands/shortcut_context.dart` |
| Dispatcher | Single root handler; owns match → invoke | `services/commands/shortcut_dispatcher.dart` |
| Settings UI | `/config/shortcuts` + settings dialog entry | `pages/config/shortcuts_config_section.dart` |

### Command definition

```text
CommandDefinition {
  id: String                    // e.g. "workbench.session.nextTab"
  category: CommandCategory     // navigation | tabs | view | zoom | compose
  defaultChords: List<KeyChord> // portable; empty = unbound by default
  when: ShortcutWhen            // always | hasWorkspace | hasOpenWorkspaceTabs | hasSessionTab | inCompose | …
  terminalPassthrough: bool     // if true, still fires when inTerminal
  titleL10nKey / descriptionL10nKey
}
```

Handlers are **not** on the definition. Features register at bootstrap or widget mount:

```text
commandBus.register('workbench.session.nextTab', () { … });
```

Unregister on dispose when the handler is chrome-scoped (e.g. `HomeShell`).

**Invoke with no handler:** silent no-op (event still marked handled if the chord matched and when/passthrough passed). Avoids races while chrome is mounting and keeps cheatsheet-visible commands safe when out of context structurally.

### Key chords (portable)

Persist and display chords in a platform-neutral form:

```text
KeyChord { key: "tab" | "w" | "digit1" | "equal" | …, mods: [mod, shift, alt, ctrl] }
```

- `mod` resolves to Meta on macOS, Control on Windows/Linux/Android.
- Explicit `ctrl` / `meta` allowed for rare platform-specific defaults.
- Matching uses Flutter `SingleActivator` (or equivalent) built from the resolved chord.
- Display labels: `⌘W` / `Ctrl+W` via a shared formatter (settings + cheatsheet + future menus).

### Effective bindings

```text
effective(commandId) = userOverrides[commandId] ?? catalog.defaultChords(commandId)
```

- Override value `[]` means **intentionally unbound**.
- Missing key in overrides means “use default”.
- `mergeWith` semantics replace per-command lists entirely (same idea as today’s compose bindings, generalized).

### Shortcut context

Derived each key event (cheap reads from focus + existing cubits):

| Flag | True when |
|------|-----------|
| `inTerminal` | Primary focus is an agent PTY or workspace shell terminal view |
| `inCompose` | Focus is a compose / multiline prompt field |
| `inTextInput` | Focus is any editable text (compose, find, settings fields, editor) |
| `hasWorkspace` | Current route is an open workspace tab |
| `hasOpenWorkspaceTabs` | Home shell has ≥1 open workspace tab (chrome list non-empty) |
| `hasSessionTab` | Active workspace has a selected session tab (not compose-only landing) |

**When evaluation:** command runs only if its `when` is satisfied.  
**Terminal rule:** if `inTerminal` and `terminalPassthrough == false`, skip even on chord match (key goes to PTY).  
**Text input:** App commands whose chord includes at least one modifier (`mod` / `ctrl` / `meta` / `alt` / `shift`) still run when `inTextInput` is true, as long as `when` and terminal rules pass — so Mod+W can close a session tab while focus is in find/editor. Unmodified keys (no modifiers) are never claimed by app commands except compose Enter (`when: inCompose`). Settings capture modal and other “press a shortcut” UIs temporarily disable the dispatcher so typing is not stolen.

### Dispatcher placement

Install `ShortcutDispatcher` once in the app shell (same level as `MaterialApp.router` child / desktop chrome), via `HardwareKeyboard.instance.addHandler`.

- Return `true` (handled) when a chord matched and when/passthrough passed — including when `CommandBus.invoke` is a silent no-op (no handler registered). Return `false` only when no command claimed the event.
- Compose fields stop using a private binding table; they either rely on the dispatcher (`when: inCompose`) or call `KeybindingResolver` from an `onKeyEvent` that delegates to the same effective map (one matcher).
- Terminal widgets must **not** swallow Mod chords before the dispatcher: prefer app-root handler ordering so the dispatcher sees events first; if a terminal engine consumes first, add an explicit pre-filter that checks passthrough commands and short-circuits.

### Handler ownership (v1 wiring)

| Command group | Owner |
|---------------|--------|
| Workspace tab next/prev/close/reopen | `HomeShell` registers while mounted (needs open-tab list + `_selectTab` / `_closeTab` / `_reopenClosedTab`) |
| Session tab next/prev/close / new | `ChatCubit` + workspace session actions (`selectTab`, `closeTab` / `closeSessionTab`, `enterComposeMode` or create-session landing) |
| Sidebar / right tools / terminal pane | `LayoutCubit` toggles (`setSidebarVisible`, `setRightToolsVisible`, `setWorkspaceTerminalVisible`) |
| Zoom in/out/reset | `LayoutCubit` stepped custom UI zoom (see below) |
| Compose submit / newline | Existing compose widgets; commands replace `KeyboardShortcutAction` |

Expose a thin `WorkspaceChromeCommandHost` (InheritedWidget or callback registry) from `HomeShell` so the bus can invoke chrome actions without importing private State methods across layers.

## v1 command catalog

Defaults use **Mod** = ⌘ macOS / Ctrl other. Titles are conceptual; l10n keys land in ARB at implement time.

### Navigation — workspace tabs

| Id | Default | When | Passthrough |
|----|---------|------|-------------|
| `workbench.workspace.nextTab` | Mod+Alt+Right | hasOpenWorkspaceTabs | yes |
| `workbench.workspace.prevTab` | Mod+Alt+Left | hasOpenWorkspaceTabs | yes |
| `workbench.workspace.closeTab` | Mod+Shift+W | hasWorkspace | yes |
| `workbench.workspace.reopenClosed` | Mod+Shift+T | always | yes |

`nextTab` / `prevTab` cycle the home-shell open-tab list (wrap). With a single open tab they are no-ops after invoke. `reopenClosed` is a silent no-op when the recently-closed list is empty.

### Navigation — session tabs

| Id | Default | When | Passthrough |
|----|---------|------|-------------|
| `workbench.session.nextTab` | Ctrl+Tab (explicit `ctrl`, all platforms) | hasWorkspace | yes |
| `workbench.session.prevTab` | Ctrl+Shift+Tab (explicit `ctrl`) | hasWorkspace | yes |
| `workbench.session.newTab` | Mod+T | hasWorkspace | yes |
| `workbench.session.closeTab` | Mod+W | hasSessionTab | yes |

**Why Ctrl+Tab not Mod+Tab:** On macOS, ⌘Tab is the OS app switcher and never reaches the app. VS Code / Cursor use **Ctrl+Tab** on every platform for editor/session cycling — same here (`mods: ["ctrl"]`, not `mod`).

**Semantics**

- **next/prev session:** cycle session-backed tabs in the active workspace bucket; wrap around. If there are zero session tabs (compose-only landing), no-op. If compose landing is showing and tabs exist, next/prev select from the current index.
- **newTab:** enter compose landing for the active workspace (same as “+” / new chat entry) — does not auto-launch a CLI until the user submits.
- **closeTab:** close the active session tab (`ChatCubit.closeTab` / equivalent); if last tab, return to compose landing.

### View

| Id | Default | When | Passthrough |
|----|---------|------|-------------|
| `workbench.view.toggleSidebar` | Mod+B | hasWorkspace | yes |
| `workbench.view.togglePanel` | Mod+J | hasWorkspace | yes |
| `workbench.view.toggleSecondarySidebar` | Mod+Alt+B | hasWorkspace | yes |

Map to `sidebarVisible`, `workspaceTerminalVisible`, `rightToolsVisible`.

### Zoom

| Id | Default | When | Passthrough |
|----|---------|------|-------------|
| `workbench.zoom.in` | Mod+Equal (and Mod+NumpadAdd) | always | yes |
| `workbench.zoom.out` | Mod+Minus (and Mod+NumpadSubtract) | always | yes |
| `workbench.zoom.reset` | Mod+Digit0 | always | yes |

**Zoom model:** shortcuts drive **interface zoom** (`uiZoomScale` / `uiZoomCustomMultiplier`), not OS text scaler.

- **in/out:** move to `custom` and adjust effective multiplier by a fixed step (e.g. 0.1), clamped to `kUiZoomMin`/`kUiZoomMax` (account for auto baseline so perceived step is stable).
- **reset:** set scale id back to `standard` (auto baseline).

### Compose (migrated)

| Id | Default | When | Passthrough |
|----|---------|------|-------------|
| `compose.submit` | Enter (no mods) | inCompose | no |
| `compose.newline` | Mod+Enter | inCompose | no |

### Meta

| Id | Default | When | Passthrough |
|----|---------|------|-------------|
| `workbench.shortcuts.showCheatsheet` | Mod+Slash | always | yes |

Opens the same cheatsheet surface as the settings page “overview” (dialog or side sheet). Does not replace the settings section.

## Persistence

Path: `<teampilotRoot>/keybindings.json` (app data root via `AppStorage` / `RuntimeLayout`).

```json
{
  "version": 1,
  "bindings": {
    "workbench.session.closeTab": [{ "key": "w", "mods": ["mod"] }],
    "workbench.zoom.in": []
  }
}
```

- Unknown command ids ignored on load (forward compatible).
- Export = copy of this file / download JSON.
- Import = validate chords + conflict scan; on conflicts require **Replace all** or cancel (same as Conflict detection). No silent partial apply.
- Reset all = delete overrides (or write `{ "version": 1, "bindings": {} }`).
- Reset one command = remove that key from `bindings`.

No migration from the old compose-only types — they are removed.

## Conflict detection

**v1 policy (simple):** two commands conflict when their effective chord lists share an identical chord, regardless of `when`. (Compose Enter vs Mod+Enter are different chords, so they do not conflict.)

**Runtime match:** after settings enforce uniqueness, at most one command owns a chord. If a bug or import slip leaves duplicates, the resolver picks the first catalog declaration order and logs a diagnostic — no multi-handler fan-out.

Settings UI:

- On rebind capture: live-check; primary action is **Replace** (remove that chord from the other command’s override list, then assign). User can cancel.
- List view: badge on conflicted rows (should be empty after a successful save).
- Import: show conflict report; user must **Replace all** or cancel — no silent partial apply.

## Settings UX

### Entry points

- Desktop settings dialog: new nav entry **Keyboard shortcuts**.
- Android hub + route: `/config/shortcuts` (`ConfigSection.shortcuts`).
- Cheatsheet: `Mod+/` and a button on the shortcuts settings page.

### Page layout

1. Search field (filter by title / chord / id).
2. Grouped list by `CommandCategory`.
3. Each row: title, current chord chips, overflow: Change / Reset / Unbind.
4. Footer actions: Reset all, Export, Import.
5. Change flow: modal “Press shortcut” listener; Escape cancels; Backspace unbinds.

Follow existing settings section patterns (`LayoutConfigWorkspace`, `WorkspaceHubEntry`). No new visual language.

## Platform notes

- **macOS / Windows / Linux:** full support; Mod as above.
- **Android:** same dispatcher when a hardware keyboard is present; settings page available; no soft-key remapping.
- **WSL / SSH storage backends:** `keybindings.json` lives on the bound app-data filesystem like other prefs.

## Testing

| Area | Tests |
|------|-------|
| Chord parse / format / platform Mod resolution | unit |
| Resolver match + when + passthrough + no-handler no-op | unit |
| Override merge, unbound, conflict scan | unit |
| ShortcutCubit rebind / reset / import | cubit + temp `AppStorage` |
| Dispatcher invokes handler and marks handled | widget or unit with fake keyboard |
| Compose migration still submits / newlines | existing compose tests updated |
| HomeShell / ChatCubit command registration | focused widget or cubit tests for next/prev/close |

## Deleted / replaced

- `KeyboardShortcutAction` enum
- Compose-only `KeyboardShortcutBindings.compose` as the sole binding source (generalized `KeybindingResolver` + catalog defaults remain)
- Any duplicate ad-hoc global handlers that the new dispatcher supersedes

## Future extension hooks (not v1)

- `workbench.action.showCommands` command palette over the same `CommandBus`.
- Menu bar accelerators reading the same effective chords.
- Chord sequences and “when clause” expressions beyond the fixed enum.
- Extension-contributed commands (after Extension remote story).

## Implementation order (guidance for plan)

1. Chord model + catalog + bus + resolver + context (no UI).
2. Dispatcher at app root + migrate compose.
3. Register v1 handlers (layout zoom/panes, chat session tabs, home workspace tabs).
4. Persistence + ShortcutCubit.
5. Settings page + cheatsheet + conflict/rebind/import/export.
6. Remove old shortcut types; l10n; analyze + tests.
