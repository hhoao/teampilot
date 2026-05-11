# Team Config Page Design

## Summary

Move team configuration out of Settings into its own standalone page, accessible from the left sidebar.

## Changes

### 1. ConfigSection enum (`cubits/config_cubit.dart`)
- Remove `team` from enum
- Default section changed to `layout`
- Result: `enum ConfigSection { members, layout, llm }`

### 2. Settings page (`pages/config_workspace.dart`)
- Remove `TeamConfigWorkspace` widget and `_LaunchOrderRow` widget
- Remove team nav item from `_ConfigNavPanel`
- Remove `ConfigSection.team` switch case
- Remove unused imports (`launch_command_builder.dart`, `perf.dart`, `team_config.dart` may need cleanup)

### 3. New page (`pages/team_config_page.dart`)
- Standalone `TeamConfigPage` StatelessWidget
- Contains `_SettingsTitleBar` + `TeamConfigWorkspace` content
- Watches `TeamCubit` for selected team
- Sidebar remains visible (uses same ShellRoute)

### 4. Sidebar (`widgets/context_sidebar.dart`)
- Add `_TeamConfigTile` between team selector and session list
- Navigates to `/team-config`
- Icon: `Icons.groups_2_outlined`, label: "Team Config"
- Settings tile now navigates to `/config/layout`

### 5. Router (`router/app_router.dart`)
- Remove `/config/team` route
- Change `/config` redirect to `/config/layout`
- Add `/team-config` → `TeamConfigPage()`

## Layout

```
Sidebar                    Team Config Page
┌──────────────┐         ┌─────────────────────────┐
│ [Team ▼]     │         │ Team Configuration      │
│ ⚙ Team Config│ ──→    │ Edit team settings      │
│──────────────│         │                         │
│ Sessions [+] │         │ [Name] [Directory]      │
│ session-1    │         │ [Extra Args]            │
│ session-2    │         │ Member Launch Order     │
│──────────────│         │ 1. team-lead   [Open]   │
│ ⚙ Settings   │         │ [Save]                  │
└──────────────┘         └─────────────────────────┘
```
