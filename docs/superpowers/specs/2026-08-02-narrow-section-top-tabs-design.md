# Narrow-width section navigation as top underline tabs

**Date:** 2026-08-02  
**Status:** approved design  
**Scope:** Skills / Plugins / MCP / Extensions library pages + workspace manage; narrow viewport (`< 840`) section nav → top underline tabs.  
**Out of scope:** App `/config`, team config, Providers, HomeSidebar drawer chrome, title-bar bell/settings.

## Problem

Desktop section pages use `WorkspaceAdaptiveSectionPage` → left nav + body.

On Android (and today via `useAndroidHubNavigation` = `Platform.isAndroid`), the adaptive page **drops the nav** and renders only `body`. Home-embedded library views (`?global=skills` etc.) therefore have **no way to switch** Installed / Discovery / Repos (and equivalents). Independent `/skills` routes compensate with a Hub list → push detail flow, but Home embed does not.

Users want the missing left-nav options available on mobile as **top tabs above the content**, matching the team identity underline tabs (`HomeContentTabBar`).

## Goals

1. On **narrow width** (`viewportWidth < WorkspacePanePolicy.narrowBreakpointWidth` = 840), show section options as a **horizontal underline tab strip** above the section body.
2. Visual parity with **`HomeContentTabBar`** (team settings / identity content shell).
3. Cover **Skills, Plugins, MCP, Extensions** and **workspace manage** via opt-in on the adaptive shell (other Adaptive callers unchanged).
4. Unify standalone **in-scope** library routes: **skip Hub list**; land on the default section page that already includes tabs.
5. Keep **wide** layout as today’s split left nav + body.

## Non-goals

- Restyling HomeSidebar / mobile drawer library entry list.
- Changing Providers (separate list/detail pattern).
- App settings (`/config`) or team-config pages in this iteration.
- Replacing `TpTabChip` / closable session strips — section tabs are non-closable underline items.
- Persisting last-selected section beyond existing route / local embed state.

## Decisions (locked)

| Topic | Decision |
|-------|----------|
| Trigger | **Width** `< 840` **and** page opts into compact section tabs |
| Opt-in | In-scope pages pass structured **`items`** + `compactSectionTabs: true` (or equivalent). Out-of-scope callers keep today’s `nav` + Android body-only / Hub flow |
| Visual | Reuse / share **`HomeContentTabBar`** underline style |
| Architecture | Extend **`WorkspaceAdaptiveSectionPage`** with an opt-in narrow-tabs branch (approach A) — **not** a global replace of Android hub behavior |
| Nav data | Structured **`WorkspaceSectionNavItem`** list (label, selected, onSelect; optional icon for wide nav only) — build left nav **or** tabs from the same list when opted in |
| Single section | **Hide** the tab strip when `items.length <= 1` |
| Standalone routes | In-scope library roots `/skills`, `/plugins`, `/mcp`, `/extensions` → default section page with tabs (no Hub intermediate) |
| Android back | After Hub removal: back from a library section (root or `/…/installed` etc.) **exits the library** (prefer `canPop` then pop; else `go` home `/home-v2`), **not** bounce to a Hub list. Update `AndroidShellChrome.pop` / `shouldHideDrawer` accordingly |
| Embed Home | Keep `onSelectSection` local-state switching; tabs call the same callback |
| Workspace manage | Same adaptive shell with opt-in; manage sections become top tabs when narrow |
| Unscoped pages | `/config`, team-config, Providers, `McpFormNavPage` — **unchanged** this iteration (still `useAndroidHubNavigation` body-only + Hub where applicable) |
| Compact helper | Width check only applies when `compactSectionTabs` is enabled |

## Architecture

```
WorkspaceAdaptiveSectionPage
  compactSectionTabs: bool (default false)
  items: List<WorkspaceSectionNavItem>?  // required when compactSectionTabs
  nav: Widget?                           // legacy / out-of-scope
  title / body / embedded / …
        │
        ├─ wide (≥840) + (items or nav)
        │     → WorkspaceHubDesktopShell (split)
        │
        ├─ narrow (<840) + compactSectionTabs + items
        │     → header + HomeContentTabBar (if items.length > 1) + body
        │
        └─ narrow/Android + !compactSectionTabs
              → WorkspaceSectionPage(body only)  // existing hub detail behavior
```

Three explicit branches — in-scope library/manage use the middle branch; config/team-config/forms stay on the last.

### `WorkspaceSectionNavItem`

```dart
class WorkspaceSectionNavItem {
  const WorkspaceSectionNavItem({
    required this.label,
    required this.selected,
    required this.onSelect,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final IconData? icon; // wide left nav only
}
```

In-scope call sites map sections → `items` once and set `compactSectionTabs: true`; desktop nav list and narrow tabs both consume `items`. Out-of-scope pages keep passing `nav` only.

### Width detection

When `compactSectionTabs` is true, use `MediaQuery.sizeOf(context).width` against `WorkspacePanePolicy.narrowBreakpointWidth`. Do **not** flip unscoped adaptive pages off `Platform.isAndroid`.

### Routing (library pages in scope)

| Before (Android) | After |
|------------------|--------|
| `/skills` → Hub list → push `/skills/installed` | `/skills` → (redirect or build) default section page with tabs |
| Same for plugins / mcp / extensions | Same |

Deep links to a specific section segment remain valid.

**`AndroidShellChrome`:** today detail back does `go('/skills')` expecting a Hub. After this change `/skills` is the tabbed section page, so:

- Back from `/skills/<section>` → same exit as back from `/skills` (leave library: pop if possible, else `/home-v2`).
- Do **not** redirect detail → root if root immediately redirects back to the same default section (loop).
- Align `shouldHideDrawer` / AppBar back affordance with “section page is the leaf,” not “Hub is the leaf.”

Hub page widgets: remove from router when redirects land on section pages; delete dead hub widgets/tests in the same change set when nothing else references them.

**Standalone chrome vs in-page header:** on Android settings chrome, prefer **one** title — either keep `AndroidShellChrome` AppBar title and hide duplicate `WorkspacePaneHeader` title when not embedded, or the reverse; tabs always stay under the remaining title. Default: keep AppBar for standalone Android routes; suppress redundant pane header title when `!embedded` on Android chrome.

### Workspace manage

`WorkspaceConfigWorkspace` already uses `WorkspaceAdaptiveSectionPage`. Opt in with manage `items`; narrow shows Settings / Skills / Plugins / MCP / Extensions as underline tabs.

### Explicitly unchanged

- `McpFormNavPage`, `/config`, `/team-config`, Providers — no compact tabs opt-in this iteration.
## UI details

- Tab strip: horizontal scroll, underline selected (`HomeContentTabBar` / `HomeContentTabItem`).
- Place strip under page title, above body; match identity shell spacing where practical (`SizedBox` + `Divider`).
- No close affordance on section tabs.
- Icons optional on wide nav rows; **omit icons on top tabs** (label-only, like team settings).
- Avoid double titles on Android standalone chrome (see Routing).

## Testing

1. **Adaptive shell:** wide + opt-in → split; narrow + opt-in → tabs; tap invokes `onSelect`; `items.length == 1` → no strip; **without** opt-in on Android → body-only (regression for unscoped).
2. **Skills** (representative): Home embed narrow — tabs switch sections; standalone `/skills` opens default section with tabs (no hub list); Android back leaves library (no hub bounce / redirect loop).
3. **Workspace manage** narrow: tabs for all manage sections; selection updates body.
4. **Regression:** wide desktop split unchanged; `/config`, team-config, Providers, MCP form nav unchanged this iteration.

## Implementation notes

- Primary file: `client/lib/widgets/settings/workspace_section_host.dart` (+ thin mobile shell widget if file size warrants).
- Reuse `HomeContentTabBar` from `home_workspace_content_header.dart`, or move the tab bar to a neutral widgets/settings path if home_workspace import would create a layering smell — prefer **move/share** over duplicating styles.
- Update Skills / Plugins / MCP / Extensions management pages and workspace config to pass `items` + `compactSectionTabs: true`.
- Router: redirect hub roots to default section; update `AndroidShellChrome.pop` / drawer-hide rules; adjust tests that expect Hub pages on Android.
