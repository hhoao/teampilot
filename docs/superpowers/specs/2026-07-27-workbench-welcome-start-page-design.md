# Workbench welcome / start page: design

## Problem

Compose landing (`WorkspaceChatLanding`) is the only full-center empty
experience when starting a new chat. There is no workbench-level **start /
welcome** surface: a session-tab strip with no selected tab, centered brand,
and actionable keyboard shortcuts (Cursor-style empty editor).

Returning from landing today either re-selects a session (`exitNewChat`) or,
when `activeTabId == null`, `WorkbenchBody` still renders compose landing —
so “no selection” and “new chat” are conflated.

## Goal

- Add a left-arrow control on compose landing that leaves compose and shows a
  **welcome / start page** inside the workbench.
- Welcome keeps existing workbench strip tabs, clears selection, and shows
  logo + curated, **executable** command shortcut rows.
- Compose remains the default when opening a workspace or choosing “new
  conversation”; welcome is **only** the back target from landing (v1).
- Make center modes explicit: **compose | welcome | tab**. Do **not** preserve
  the legacy meaning `activeTabId == null` ⇒ landing.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Target surface | Workbench empty state (session/file/shell tab strip visible), not Home library |
| Tabs on back | Keep tab order; clear active selection only |
| Entry to welcome | Landing ← only in v1 |
| Open workspace / New chat | Still enter **compose** |
| Empty tab strip + ← | Still **welcome** (do not force compose like `exitNewChat`) |
| Shortcuts | Real `CommandBus.invoke` + effective chords from `ShortcutCubit` |
| Architecture | Explicit center mode; no backward-compat for null-active → landing |
| Open Browser (mockup) | Omit until a matching command exists |

## Non-goals (v1)

- Changing Home (`/home-v2`) library content to a shortcuts welcome
- Defaulting workspace open to welcome instead of compose
- Full cheatsheet as the welcome body (curated rows only)
- Migrating or dual-pathing old `active == null → WorkspaceChatPane` callers
- Adding a Browser / external URL command solely for visual parity

## Architecture

### Center mode

```
newChatActive == true          → compose
else if activeTabId == null    → welcome
else                           → tab(activeTabId)
```

Encode this as a small pure helper (e.g. `resolveWorkbenchCenterMode`) used by
IDE center / `WorkbenchBody` / tests — single source of truth.

| Mode | Chrome | Body |
|------|--------|------|
| **compose** | No workbench strip (today’s `buildWorkspaceIdeCenter(newChat: true)` path, or equivalent single compose host) | `WorkspaceChatLanding` (+ back affordance) |
| **welcome** | `WorkspaceShell` tab strip (tabs retained, none active) | `WorkbenchWelcomePage` |
| **tab** | Tab strip with selection | Existing session / file / diff / shell / run surfaces |

### Navigation

```
compose  --(landing ←)-->  welcome
welcome  --(select tab / open file…)-->  tab
welcome  --(sessionNewTab / New conversation)-->  compose
tab      --(enterNewChat + clearActive)-->  compose   // existing
```

Landing ← **must not** call `exitNewChat` (that re-selects a session). Use:

1. `ChatCubit.dismissNewChat()`
2. `WorkbenchCubit.clearActive(workspaceId)`

### Cleanup (intentional break)

- Remove `WorkbenchBody` branch: `active == null → WorkspaceChatPane`.
- Compose mounts only via the compose-mode path (`newChatActive`), not as the
  null-active fallback.
- Any prior caller of `clearActive` that expected landing now gets **welcome**.

```
WorkspaceIdeShell / ChatPageShell
 ├─ compose → WorkspaceChatLanding
 └─ !compose → WorkspaceShell (tabs)
                 └─ WorkbenchBody
                      ├─ welcome (active == null)
                      └─ tab surfaces (active != null)
```

### Module placement

| Location | Contents |
|----------|----------|
| `client/lib/pages/workbench/workbench_welcome_page.dart` | Centered logo + shortcut list UI |
| `client/lib/services/workbench/` (or adjacent helper) | `resolveWorkbenchCenterMode`, curated welcome command ids |
| `workspace_chat_landing.dart` | Top-leading back button |
| `WorkbenchBody` / IDE center | Mode switch; drop null → landing |
| l10n `app_en.arb` / `app_zh.arb` | Back tooltip / “unbound” chord label if needed |

## Product UX

### Landing back control

- Top-**leading** (左上角) icon button: back arrow (`Icons.arrow_back` or Tp equivalent).
- Outside the compose card (overlay / shell chrome of the landing page).
- Tooltip: e.g. “Back to start” / 「返回启动页」.
- Action: dismiss compose + clear workbench active → welcome.

### Welcome page

- Full center fill; content vertically and horizontally centered.
- Large `TeamPilotBrandLogo` above the list (muted / monochrome onSurface OK).
- Fixed-width shortcut column: label left, keycap(s) right.
- Visual language: dark/theme surface, keycaps like shortcuts cheatsheet chips;
  no card grid, no marketing copy.

### Curated commands (v1)

| Order | `CommandIds` | Role |
|------:|--------------|------|
| 1 | `sessionNewTab` | New conversation → compose |
| 2 | `togglePanel` | Terminal panel |
| 3 | `toggleSidebar` | Sidebar / files |
| 4 | `workspaceSearch` | Go to / search workspace |
| 5 | `showCheatsheet` | Full shortcut list |

- Labels: `titleForCommand(l10n, id)`.
- Keycaps: effective chords from `ShortcutCubit` + `formatKeyChord` (Mac/Win).
- Row tap: `CommandBus.invoke(id)` (same as keyboard path intent).
- Unbound: still tappable; right side shows muted unbound label (l10n), not empty.
- Missing handler: `invoke` remains silent no-op (existing `CommandBus`).

Row click vs global shortcut `when`: prefer **row always invokes**; global
dispatcher keeps its `when` gates. Document this in the plan/tests.

## Data / state notes

- Welcome is **derived**, not a persisted flag: `!newChatActive && activeTabId == null`.
- Tab order and pin state unchanged across landing ↔ welcome.
- Per workspace `tabScopeId` / workbench bucket — no cross-workspace bleed.
- `exitNewChat` behavior for empty tabs (re-enter compose) stays for that API;
  landing ← uses dismiss + clearActive instead.

## Error handling

- No user-visible error if a welcome row’s command has no handler.
- Back action is local state only (no IO); no toast required.

## Testing

| Area | Cases |
|------|--------|
| Mode helper | Truth table: `newChatActive` × `activeTabId` → compose / welcome / tab |
| Navigation | ← keeps `tabOrder`, sets active null, clears `newChatActive`; empty tabs → welcome not compose |
| Welcome list | Curated ids stable; chord labels follow effective bindings |
| Regression | `clearActive` no longer implies compose body |
| Widget (optional) | Landing exposes back control; row tap invokes bus |

## Implementation sketch (for writing-plans)

1. Add `resolveWorkbenchCenterMode` + curated command id list + unit tests.
2. Implement `WorkbenchWelcomePage`; wire into `WorkbenchBody` for welcome.
3. Ensure compose-only path for `newChatActive`; delete null → landing.
4. Landing back button → `dismissNewChat` + `clearActive`.
5. Update any tests/docs that assumed null-active compose; run analyze + unit tests.

## Open questions

None for v1 — decisions locked above.
