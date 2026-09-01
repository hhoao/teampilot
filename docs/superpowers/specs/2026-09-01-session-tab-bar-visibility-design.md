# Session tab bar visibility setting — Design

Date: 2026-09-01
Status: Approved (design dialogue)

## Summary

Add a persisted preference that hides the workspace center tab strip (the
session / editor / terminal tab bar, including the "+" new-chat button). The
strip is hidden as a whole — no per-tab-kind filtering, no compensating UI.
Toggle lives in Settings → Layout → Region Visibility as a switch, following
the existing region-visibility pattern.

## Requirements

- The entire `WorkspaceShellTabRow` (session chips, editor/terminal chips,
  reorder, trailing actions area, and the `WorkspaceShellNewChatButton`) is
  not rendered when the preference is off.
- Preference persists across restarts (`LayoutRepository`, SharedPreferences).
- Default is visible: existing configs without the JSON key keep the tab bar.
- Session switching still works via the sidebar session list; new-conversation
  entry points outside the strip (sidebar, landing) remain untouched — pure
  hide, nothing added.
- No per-workspace granularity; one global preference.

## Non-goals

- No quick-toggle button in the title bar (user chose settings-page-only
  entry).
- No per-tab-kind partial hiding.
- No new floating "+" / active-session indicator while hidden.

## Approach (selected)

Follow the existing region-visibility pattern: a bool on
`LayoutPreferences` + a one-line setter on `LayoutCubit` + a switch row in
`LayoutRegionVisibilitySection`. Alternatives rejected: in-memory-only
override (lost on restart, contradicts "配置"), per-workspace state on
`WorkbenchCubit` (unrequested granularity, wrong layer).

## Changes

### 1. Model — `client/lib/models/layout_preferences.dart`

- New field `final bool sessionTabBarVisible;`, default `true`,
  constructor param `this.sessionTabBarVisible = true`.
- `fromJson`: `sessionTabBarVisible: json['sessionTabBarVisible'] as bool? ?? true`.
- `copyWith` + `toJson`: add the key (`'sessionTabBarVisible'`).
- Thread through `withAtLeastOneToolVisible`'s reconstructed instance (it
  builds a full `LayoutPreferences`, so the field must be passed along).

### 2. Cubit — `client/lib/cubits/layout_cubit.dart`

- `Future<void> setSessionTabBarVisible(bool visible) => _save(
  state.preferences.copyWith(sessionTabBarVisible: visible));`
  placed beside `setSidebarVisible` / region setters. No drawer-mode side
  effects — the tab strip is desktop-center chrome, unrelated to mobile
  drawer snapshots.

### 3. Shell — `client/lib/pages/workspace_shell/workspace_shell.dart`

- New param `final bool showTabBar;` default `true`.
- Guard becomes `if (showTabBar && (tabs.isNotEmpty || showNewChatButton))`.
- When hidden and `actions.isNotEmpty && showHeader`, the existing fallback
  `WorkspaceShellActionsBar` still renders actions (unchanged behavior —
  `_ChatWorkspaceShell` passes no team actions for personal contexts and team
  actions only for teams; those render in the actions bar exactly as they do
  today when the strip is empty).
- `WorkspaceShellTabRow` itself is unchanged; other potential callers keep
  current behavior.

### 4. Caller — `client/lib/pages/chat/chat_page_shell.dart`

- In `_ChatWorkspaceShell.build`, read
  `context.select<LayoutCubit, bool>((c) => c.state.preferences.sessionTabBarVisible)`
  and pass it as `showTabBar` to `WorkspaceShell`.

### 5. Settings UI — `client/lib/pages/config/layout_region_visibility_section.dart`

- New `TpPreferenceRow` after the "Tools panel" row:
  - title: `l10n.sessionTabBarTitle` ("Session tab bar" / 「会话标签栏」)
  - subtitle: `l10n.sessionTabBarVisibilityHint`
    ("Show the tab strip above the workbench center column." /
    「在工作台中心列上方显示标签栏。」)
  - trailing: `Switch` wired to `controller.setSessionTabBarVisible`.
- `BlocSelector` tuple widens from 5 to 6 bools to include the new value.
- Layout section data flow unchanged (the section is reached via
  `layout_config_section.dart`).

### 6. AppKeys — `client/lib/utils/ui/app_keys.dart`

- `static const sessionTabBarVisibilitySwitch =
  Key('session-tab-bar-visibility-switch');` beside the other visibility
  switches (kebab-case, matching `right-tools-visibility-switch`).

### 7. l10n — `client/lib/l10n/app_en.arb`, `app_zh.arb`

- `sessionTabBarTitle`, `sessionTabBarVisibilityHint` in both files (English
  + 简体中文). No other ARB edits.

## Data flow

`Switch` → `LayoutCubit.setSessionTabBarVisible` → `_save` emits new state and
persists via `LayoutRepository` → `context.select` in `_ChatWorkspaceShell`
rebuilds → `WorkspaceShell` skips the tab row. Restart:
`LayoutCubit.load()` → repository JSON → `fromJson` default `true` when key
absent.

## Error handling

None beyond existing persistence failure paths (repository is
SharedPreferences; malformed key falls back to `true` via `?? true`). No new
IO, no user-facing error states.

## Testing

- `client/test/cubits/layout_cubit_preferences_test.dart`: persistence
  round-trip — `setSessionTabBarVisible(false)`, state reflects `false`,
  reload from repository keeps `false`; default load (empty store) yields
  `true`.
- `client/test/pages/workspace_shell_test.dart`: widget test —
  `WorkspaceShell(showTabBar: false, tabs: [...], showNewChatButton: true)`
  renders neither `WorkspaceShellTabRow` nor `WorkspaceShellNewChatButton`
  while the child stays visible; default (`showTabBar` omitted) keeps
  rendering the row.
- `client/test/pages/config/layout_region_visibility_section_test.dart`:
  new switch test — defaults `true`, tapping the
  `AppKeys.sessionTabBarVisibilitySwitch` switch sets the cubit to `false`
  and the widget state updates (same shape as the existing right-tools
  switch test).
- Gate: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings &&
  dart run tool/run_tests.dart`.

## Risks / notes

- Tab strip also carries the trailing actions wrap for team sessions; with
  `showHeader: false` (current `_ChatWorkspaceShell` usage) actions move to
  the fallback `WorkspaceShellActionsBar`, which already exists for the
  no-tabs case — no dead end for team actions.
- Mobile uses drawers for panes; the strip is hidden behind the same global
  flag there too (acceptable — the strip is center chrome on both, and the
  user asked for one global setting).
- `preview` tabs and pinned session ordering logic are untouched; only
  rendering is gated.
